import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_models.dart';
import 'sigv4.dart';

/// Something went wrong talking to R2, with a sentence to show.
class R2Exception implements Exception {
  const R2Exception(this.message, {this.status = 0});
  final String message;

  /// The HTTP status (0: no answer at all).
  final int status;

  /// The keys were refused (wrong, or not allowed to write to this bucket).
  bool get refused => status == 401 || status == 403;

  @override
  String toString() => message;
}

/// Reads and writes files in one R2 bucket, signing each request with the user's keys.
class R2Client {
  R2Client(this.config, {http.Client? client, DateTime Function()? now, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final CloudConfig config;
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;

  late final SigV4 _signer = SigV4(accessKeyId: config.accessKeyId.trim(), secretKey: config.secretKey.trim());

  /// A key is a plain path inside the bucket.
  static bool validKey(String key) => RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$').hasMatch(key) && !key.contains('..');

  Map<String, String> _headers(String method, String key, String payloadHash) {
    final path = '/${config.bucket.trim()}/$key';
    return _signer.sign(method: method, host: config.host, path: path, payloadHash: payloadHash, now: _now());
  }

  Uri _uri(String key) => Uri.https(config.host, '/${config.bucket.trim()}/$key');

  R2Exception _failed(int status) {
    if (status == 401 || status == 403) {
      return R2Exception('R2 refused the keys. Check the access key id and the secret, and that the key may write to this bucket.', status: status);
    }
    if (status == 404) return R2Exception('The bucket or the file was not found. Check the bucket name and the account id.', status: status);
    if (status == 429 || status >= 500) return R2Exception('Cloudflare is busy. Try again in a moment.', status: status);
    return R2Exception('Cloudflare did not accept that (error $status).', status: status);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run().timeout(timeout);
    } on R2Exception {
      rethrow;
    } catch (_) {
      throw const R2Exception('No internet connection, or Cloudflare did not answer.');
    }
  }

  /// The bytes of a file, or null if it is not there.
  Future<Uint8List?> get(String key) => _guard(() async {
        if (!validKey(key)) throw const R2Exception('That is not a valid file name.');
        final res = await _client.get(_uri(key), headers: _headers('GET', key, SigV4.sha256Hex(const [])));
        if (res.statusCode == 404) return null;
        if (res.statusCode != 200) throw _failed(res.statusCode);
        return res.bodyBytes;
      });

  /// Puts a small file (the catalog, a cover).
  Future<void> putBytes(String key, List<int> bytes, {required String contentType, String? cacheControl}) => _guard(() async {
        if (!validKey(key)) throw const R2Exception('That is not a valid file name.');
        final res = await _client.put(
          _uri(key),
          headers: {
            ..._headers('PUT', key, SigV4.sha256Hex(bytes)),
            'content-type': contentType,
            if (cacheControl != null) 'cache-control': cacheControl,
          },
          body: bytes,
        );
        if (res.statusCode != 200 && res.statusCode != 201) throw _failed(res.statusCode);
      });

  /// Puts a big file as a stream (a song), so it is not held in memory whole.
  Future<void> putStream(String key, Stream<List<int>> data, int length, {required String contentType}) => _guard(() async {
        if (!validKey(key)) throw const R2Exception('That is not a valid file name.');
        final req = http.StreamedRequest('PUT', _uri(key))
          ..headers.addAll({
            ..._headers('PUT', key, SigV4.unsignedPayload),
            'content-type': contentType,
          })
          ..contentLength = length;
        // Fed in the background; an error while reading the file ends the request with it.
        data.listen(req.sink.add, onError: req.sink.addError, onDone: req.sink.close, cancelOnError: true);
        final res = await _client.send(req);
        await res.stream.drain<void>();
        if (res.statusCode != 200 && res.statusCode != 201) throw _failed(res.statusCode);
      });

  Future<void> delete(String key) => _guard(() async {
        if (!validKey(key)) throw const R2Exception('That is not a valid file name.');
        final res = await _client.delete(_uri(key), headers: _headers('DELETE', key, SigV4.sha256Hex(const [])));
        if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 404) throw _failed(res.statusCode);
      });
}
