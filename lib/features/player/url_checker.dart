import 'dart:async';
import 'dart:io';

import '../../core/protocol/protocol.dart';
import 'playback_engine.dart';

/// Quick pre-flight check of an internet audio URL, so the user gets a clear
/// reason when a link can't work (no internet, wrong address, a web page
/// instead of audio) rather than a vague player error.
abstract class UrlChecker {
  /// Returns normally if the URL looks playable. Throws a [PlaybackException]
  /// with [ErrorCodes.invalidUrl] or [ErrorCodes.urlUnreachable] otherwise.
  Future<void> check(Uri uri);
}

class HttpUrlChecker implements UrlChecker {
  HttpUrlChecker({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;

  @override
  Future<void> check(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'RemoteTunes';
    try {
      var result = await _probe(client, uri, head: true).timeout(timeout);
      // Many servers refuse HEAD; ask for the first byte instead.
      if (result.status >= 400) {
        result = await _probe(client, uri, head: false).timeout(timeout);
      }
      _judge(result);
    } on PlaybackException {
      rethrow;
    } on TimeoutException {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        'The website took too long to answer. Check the internet connection on the Player phone and try again.',
      );
    } on HandshakeException {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        "A secure connection to that website couldn't be made (certificate problem).",
      );
    } on TlsException {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        "A secure connection to that website couldn't be made (certificate problem).",
      );
    } on SocketException {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        "The Player couldn't reach that website. Make sure the Player phone is connected to the internet and the link is right.",
      );
    } on HttpException {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        "The website's answer couldn't be read.",
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_Probe> _probe(HttpClient client, Uri uri, {required bool head}) async {
    final request = head ? await client.headUrl(uri) : await client.getUrl(uri);
    if (!head) request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close();
    final type = response.headers.contentType;
    final probe = _Probe(
      response.statusCode,
      type == null ? null : '${type.primaryType}/${type.subType}',
    );
    // Drop the body; only the headers matter.
    unawaited(response.drain<void>().catchError((_) {}));
    return probe;
  }

  void _judge(_Probe p) {
    if (p.status == 401 || p.status == 403) {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        'The website refused access to that link (error ${p.status}).',
      );
    }
    if (p.status == 404 || p.status == 410) {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        "That link wasn't found on the website (error ${p.status}). Check the address.",
      );
    }
    if (p.status >= 400) {
      throw PlaybackException(
        ErrorCodes.urlUnreachable,
        'The website answered with an error (${p.status}). Try again later.',
      );
    }
    final type = p.contentType ?? '';
    if (type == 'text/html' || type == 'application/xhtml+xml') {
      throw PlaybackException(
        ErrorCodes.invalidUrl,
        'This link opens a web page, not an audio file. Use a direct link to '
        'an audio file (for example one ending in .mp3).',
      );
    }
  }
}

class _Probe {
  const _Probe(this.status, this.contentType);

  final int status;
  final String? contentType;
}
