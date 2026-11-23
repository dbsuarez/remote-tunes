import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/url_checker.dart';

void main() {
  late HttpServer server;
  late String base;
  final heads = <String>[];
  final gets = <String>[];

  setUp(() async {
    heads.clear();
    gets.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      final isHead = req.method == 'HEAD';
      (isHead ? heads : gets).add(path);
      final res = req.response;
      switch (path) {
        case '/ok.mp3':
          res.headers.contentType = ContentType('audio', 'mpeg');
        case '/nohead.mp3':
          if (isHead) {
            res.statusCode = 405;
          } else {
            res.statusCode = 206;
            res.headers.contentType = ContentType('audio', 'mpeg');
          }
        case '/page':
          res.headers.contentType = ContentType.html;
        case '/binary':
          res.headers.contentType = ContentType.binary;
        case '/notype':
          break;
        case '/missing':
          res.statusCode = 404;
        case '/gone':
          res.statusCode = 410;
        case '/forbidden':
          res.statusCode = 403;
        case '/boom':
          res.statusCode = 500;
        case '/redirect':
          res.statusCode = 302;
          res.headers.set('location', '/ok.mp3');
        case '/slow':
          await Future<void>.delayed(const Duration(seconds: 3));
          res.headers.contentType = ContentType('audio', 'mpeg');
        default:
          res.statusCode = 404;
      }
      try {
        await res.close();
      } catch (_) {}
    });
  });

  tearDown(() => server.close(force: true));

  Future<void> expectFails(String path, String code, {Object? message, UrlChecker? checker}) async {
    await expectLater(
      (checker ?? HttpUrlChecker()).check(Uri.parse('$base$path')),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', code)
          .having((e) => e.message, 'message', message ?? isNotEmpty)),
    );
  }

  test('accepts an audio link', () async {
    await HttpUrlChecker().check(Uri.parse('$base/ok.mp3'));
    expect(heads, ['/ok.mp3']);
    expect(gets, isEmpty);
  });

  test('accepts generic or missing content types (not every server labels audio)',
      () async {
    await HttpUrlChecker().check(Uri.parse('$base/binary'));
    await HttpUrlChecker().check(Uri.parse('$base/notype'));
  });

  test('follows redirects', () async {
    await HttpUrlChecker().check(Uri.parse('$base/redirect'));
  });

  test('falls back to a GET when the server refuses HEAD', () async {
    await HttpUrlChecker().check(Uri.parse('$base/nohead.mp3'));
    expect(heads, ['/nohead.mp3']);
    expect(gets, ['/nohead.mp3']);
  });

  test('a web page is not audio (INVALID_URL)', () async {
    await expectFails('/page', ErrorCodes.invalidUrl, message: contains('web page'));
  });

  test('404 / 410 mean the link was not found', () async {
    await expectFails('/missing', ErrorCodes.urlUnreachable, message: contains('404'));
    await expectFails('/gone', ErrorCodes.urlUnreachable, message: contains('410'));
  });

  test('403 means access was refused', () async {
    await expectFails('/forbidden', ErrorCodes.urlUnreachable, message: contains('refused'));
  });

  test('server errors are reported with the status', () async {
    await expectFails('/boom', ErrorCodes.urlUnreachable, message: contains('500'));
  });

  test('a slow server times out with a clear message', () async {
    await expectFails(
      '/slow',
      ErrorCodes.urlUnreachable,
      message: contains('too long'),
      checker: HttpUrlChecker(timeout: const Duration(milliseconds: 300)),
    );
  });

  test('no connection (closed port) says the Player cannot reach the website',
      () async {
    final port = server.port;
    await server.close(force: true);
    await expectLater(
      HttpUrlChecker(timeout: const Duration(seconds: 2))
          .check(Uri.parse('http://127.0.0.1:$port/ok.mp3')),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', ErrorCodes.urlUnreachable)
          .having((e) => e.message, 'message', contains('internet'))),
    );
    // tearDown closes it again: harmless.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  test('an unknown host name is unreachable, not a crash', () async {
    await expectLater(
      HttpUrlChecker(timeout: const Duration(seconds: 5))
          .check(Uri.parse('http://no-such-host.invalid/a.mp3')),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', ErrorCodes.urlUnreachable)),
    );
  });
}
