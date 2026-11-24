import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Where updates are published: the GitHub Releases of this app.
const kUpdateRepo = 'dbsuarez/remote-tunes';

/// A newer version found on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.size,
    this.sha256,
  });

  /// e.g. `0.2.0` (no leading "v").
  final String version;
  final String notes;
  final String apkUrl;
  final String apkName;
  final int size;

  /// Expected SHA-256 of the file (hex), when GitHub gives one.
  final String? sha256;
}

/// A plain-language problem while checking, downloading or installing.
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Splits `1.2.3` (an optional leading `v`, anything after `-` or `+` ignored)
/// into numbers. Missing parts count as 0; junk gives null.
List<int>? parseVersion(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split(RegExp('[-+]')).first;
  if (s.isEmpty) return null;
  final parts = <int>[];
  for (final p in s.split('.')) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    parts.add(n);
  }
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

/// True when [candidate] is a higher version than [current].
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Looks for a newer release on GitHub and downloads its APK.
class UpdateChecker {
  UpdateChecker({http.Client? client, this.repo = kUpdateRepo})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String repo;

  String get _downloadPrefix => 'https://github.com/$repo/releases/download/';

  /// The newest release if it is newer than [currentVersion] and has an APK for
  /// [abi]; null when this app is up to date.
  Future<UpdateInfo?> latest({required String currentVersion, required String abi}) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw UpdateException('GitHub did not answer. Check the internet connection.');
    } catch (_) {
      throw UpdateException("Couldn't reach GitHub. Check the internet connection.");
    }
    if (res.statusCode == 404) return null; // no release published yet
    if (res.statusCode != 200) {
      throw UpdateException('GitHub said no (${res.statusCode}). Try again later.');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw UpdateException("GitHub's answer could not be read.");
    }
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = (json['tag_name'] as String?) ?? '';
    if (!isNewerVersion(tag, currentVersion)) return null;

    final assets = (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>();
    Map<String, dynamic>? pick;
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      final url = (a['browser_download_url'] as String?) ?? '';
      if (name.endsWith('-release.apk') &&
          name.contains(abi) &&
          url.startsWith(_downloadPrefix)) {
        pick = a;
        break;
      }
    }
    if (pick == null) {
      throw UpdateException('Version $tag has no download for this phone ($abi).');
    }
    final digest = (pick['digest'] as String?) ?? '';
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: ((json['body'] as String?) ?? '').trim(),
      apkUrl: pick['browser_download_url'] as String,
      apkName: pick['name'] as String,
      size: (pick['size'] as num?)?.toInt() ?? 0,
      sha256: digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
    );
  }

  /// True when [file] is the complete, unchanged APK of [info].
  Future<bool> _isGoodDownload(File file, UpdateInfo info) async {
    try {
      if (!file.existsSync()) return false;
      if (info.size > 0 && file.lengthSync() != info.size) return false;
      final want = info.sha256;
      if (want != null) {
        final got = (await sha256.bind(file.openRead()).first).toString();
        return got == want;
      }
      // Without a checksum only a file of the right size counts.
      return info.size > 0;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the APK of [info] into [dir] and checks it is complete and
  /// unchanged. [onProgress] gets 0..1.
  Future<File> download(UpdateInfo info, Directory dir,
      {void Function(double progress)? onProgress}) async {
    if (!info.apkUrl.startsWith(_downloadPrefix)) {
      throw UpdateException("That download link is not from this app's releases.");
    }
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${info.apkName}');
    // Already downloaded (an earlier try that was not finished at Android's
    // install screen): use it, so tapping Update again does not download again.
    if (await _isGoodDownload(file, info)) {
      onProgress?.call(1);
      return file;
    }
    for (final old in dir.listSync()) {
      if (old is File) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    }
    final sink = file.openWrite();
    var ok = false;
    try {
      final res = await _client
          .send(http.Request('GET', Uri.parse(info.apkUrl)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw UpdateException('The download failed (${res.statusCode}).');
      }
      final total = res.contentLength ?? info.size;
      var got = 0;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      ok = true;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw UpdateException('The download stalled. Try again.');
    } catch (_) {
      throw UpdateException('The download was interrupted. Try again.');
    } finally {
      await sink.close();
      if (!ok) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
    if (info.size > 0 && file.lengthSync() != info.size) {
      file.deleteSync();
      throw UpdateException('The download is incomplete. Try again.');
    }
    final want = info.sha256;
    if (want != null) {
      final got = (await sha256.bind(file.openRead()).first).toString();
      if (got != want) {
        file.deleteSync();
        throw UpdateException('The download does not match what GitHub published. Try again.');
      }
    }
    return file;
  }
}

/// This phone's side of an update (see `UpdateSupport.kt`).
abstract class UpdateNative {
  /// Installed version name, build number and CPU type; null when unavailable
  /// (not Android).
  Future<({String version, int build, String abi})?> info();
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<void> install(String path);
}

class MethodChannelUpdateNative implements UpdateNative {
  static const _channel = MethodChannel('remotetunes/update');

  @override
  Future<({String version, int build, String abi})?> info() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('info');
      if (m == null) return null;
      return (
        version: (m['version'] as String?) ?? '0.0.0',
        build: (m['build'] as num?)?.toInt() ?? 0,
        abi: (m['abi'] as String?) ?? 'arm64-v8a',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  @override
  Future<void> install(String path) async {
    try {
      await _channel.invokeMethod<void>('install', {'path': path});
    } on PlatformException catch (e) {
      throw UpdateException("Android couldn't start the install (${e.message ?? 'unknown'}).");
    }
  }
}
