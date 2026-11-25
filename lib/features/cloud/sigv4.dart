import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Signs a request the way S3 (and Cloudflare R2) asks for: AWS Signature Version 4.
class SigV4 {
  SigV4({required this.accessKeyId, required this.secretKey, this.region = 'auto', this.service = 's3'});

  final String accessKeyId;
  final String secretKey;
  final String region;
  final String service;

  /// The body is not hashed (R2 accepts this over https), which lets a big file be sent as a stream.
  static const unsignedPayload = 'UNSIGNED-PAYLOAD';

  static String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static String sha256Hex(List<int> data) => hex(sha256.convert(data).bytes);

  static List<int> _hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  /// `20130524T000000Z`.
  static String stamp(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Percent-encodes the way the signature wants (each path piece; slashes are kept).
  static String encodePath(String path) =>
      path.split('/').map((p) => Uri.encodeComponent(p).replaceAll('+', '%20')).join('/');

  /// The headers to send ([host] and the x-amz ones are included; add Content-Type and the like
  /// yourself, and name them in [extraSigned] only if they should be part of the signature).
  ///
  /// [path] is the path as it is sent (`/bucket/songs/a.mp3`), [query] the query parameters.
  Map<String, String> sign({
    required String method,
    required String host,
    required String path,
    Map<String, String> query = const {},
    Map<String, String> extraSigned = const {},
    required String payloadHash,
    required DateTime now,
  }) {
    final date = stamp(now);
    final day = date.substring(0, 8);
    final headers = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': date,
      for (final e in extraSigned.entries) e.key.toLowerCase(): e.value.trim(),
    };
    final names = headers.keys.toList()..sort();
    final canonicalHeaders = [for (final n in names) '$n:${headers[n]}\n'].join();
    final signedHeaders = names.join(';');
    final q = query.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQuery = [
      for (final e in q) '${Uri.encodeQueryComponent(e.key).replaceAll('+', '%20')}=${Uri.encodeQueryComponent(e.value).replaceAll('+', '%20')}',
    ].join('&');
    final canonicalRequest = [
      method,
      encodePath(path),
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '$day/$region/$service/aws4_request';
    final toSign = ['AWS4-HMAC-SHA256', date, scope, sha256Hex(utf8.encode(canonicalRequest))].join('\n');
    var key = _hmac(utf8.encode('AWS4$secretKey'), day);
    key = _hmac(key, region);
    key = _hmac(key, service);
    key = _hmac(key, 'aws4_request');
    final signature = hex(Hmac(sha256, key).convert(utf8.encode(toSign)).bytes);
    return {
      for (final n in names) if (n != 'host') n: headers[n]!,
      'authorization': 'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }
}
