import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_models.dart';
import 'cloud_service.dart';

/// Where the Cloud Library settings are kept: on this device only. The keys are never put in the
/// repository, never in a backup, and never sent anywhere except to Cloudflare when uploading.
abstract class CloudConfigStore {
  Future<CloudConfig> load();
  Future<void> save(CloudConfig config);

  /// Forgets the access keys but keeps the public address (so this phone can still browse and play).
  Future<void> clearKeys();
  Future<void> clear();
}

class PrefsCloudConfigStore implements CloudConfigStore {
  PrefsCloudConfigStore([Future<SharedPreferences>? prefs]) : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;
  static const _account = 'rt.cloud_account';
  static const _bucket = 'rt.cloud_bucket';
  static const _url = 'rt.cloud_url';
  static const _keyId = 'rt.cloud_key_id';
  static const _secret = 'rt.cloud_secret';

  @override
  Future<CloudConfig> load() async {
    try {
      final p = await _prefs;
      String t(String k) => p.getString(k)?.trim() ?? '';
      return CloudConfig(
        accountId: t(_account),
        bucket: t(_bucket),
        publicUrl: t(_url),
        accessKeyId: t(_keyId),
        secretKey: t(_secret),
      );
    } catch (_) {
      return const CloudConfig();
    }
  }

  @override
  Future<void> save(CloudConfig c) async {
    final p = await _prefs;
    Future<void> put(String k, String v) => v.trim().isEmpty ? p.remove(k) : p.setString(k, v.trim());
    await put(_account, c.accountId);
    await put(_bucket, c.bucket);
    await put(_url, c.publicUrl);
    await put(_keyId, c.accessKeyId);
    await put(_secret, c.secretKey);
  }

  @override
  Future<void> clearKeys() async {
    final p = await _prefs;
    await p.remove(_keyId);
    await p.remove(_secret);
  }

  @override
  Future<void> clear() async {
    final p = await _prefs;
    for (final k in [_account, _bucket, _url, _keyId, _secret]) {
      await p.remove(k);
    }
  }
}

final cloudConfigStoreProvider = Provider<CloudConfigStore>((ref) => PrefsCloudConfigStore());

/// The Cloud Library settings; read again (invalidate) after they are saved.
final cloudConfigProvider = FutureProvider<CloudConfig>((ref) => ref.watch(cloudConfigStoreProvider).load());

/// Lets the user pick a notes file and gives its text (null: nothing picked). Replaced in tests.
final cloudNotesPickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final f = r?.files.singleOrNull;
      if (f == null) return null;
      final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
      // A notes file is small; anything big is not one.
      if (bytes == null || bytes.length > 64 * 1024) return null;
      return utf8.decode(bytes, allowMalformed: true);
    });

/// Makes a Cloud Library service for some settings (replaced in tests).
final cloudServiceFactoryProvider = Provider<CloudLibraryService Function(CloudConfig)>((ref) => CloudLibraryService.new);

/// The Cloud Library for the current settings.
final cloudServiceProvider = FutureProvider<CloudLibraryService>((ref) async {
  return ref.watch(cloudServiceFactoryProvider)(await ref.watch(cloudConfigProvider.future));
});
