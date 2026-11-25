import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_config_store.dart';
import 'cloud_models.dart';
import 'r2_client.dart';

/// Settings > Lyrics and online > Cloud Library: where your cloud songs live, and the keys to upload.
class CloudSettingsScreen extends ConsumerStatefulWidget {
  const CloudSettingsScreen({super.key});

  @override
  ConsumerState<CloudSettingsScreen> createState() => _CloudSettingsScreenState();
}

class _CloudSettingsScreenState extends ConsumerState<CloudSettingsScreen> {
  final _url = TextEditingController();
  final _account = TextEditingController();
  final _bucket = TextEditingController();
  final _keyId = TextEditingController();
  final _secret = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  bool _showSecret = false;
  String? _message;
  bool _good = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_url, _account, _bucket, _keyId, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = await ref.read(cloudConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _url.text = c.publicUrl;
      _account.text = c.accountId;
      _bucket.text = c.bucket;
      _keyId.text = c.accessKeyId;
      _secret.text = c.secretKey;
      _loaded = true;
    });
  }

  CloudConfig get _config {
    // The S3 address can be pasted into the account field: it holds the account id (and the bucket).
    final s3 = CloudConfig.parseS3Address(_account.text);
    return CloudConfig(
        publicUrl: _url.text.trim(),
        accountId: s3?.accountId ?? _account.text.trim(),
        bucket: _bucket.text.trim().isEmpty && s3 != null ? s3.bucket : _bucket.text.trim(),
        accessKeyId: _keyId.text.trim(),
        secretKey: _secret.text.trim(),
      );
  }

  void _say(String text, {bool good = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _good = good;
    });
  }

  /// Does what [run] says with the settings as typed, after saving them.
  Future<void> _act(Future<void> Function(CloudConfig c) run, {bool writing = false}) async {
    final c = _config;
    final problem = c.problem(forWriting: writing);
    if (problem != null) {
      _say(problem);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cloudConfigStoreProvider).save(c);
      ref.invalidate(cloudConfigProvider);
      await run(c);
    } on R2Exception catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _act((c) async => _say('Saved.', good: true));

  Future<void> _testPublic() => _act((c) async {
        final cat = await ref.read(cloudServiceFactoryProvider)(c).fetchCatalog();
        _say(cat.isEmpty ? 'The address works. Nothing is in the cloud yet.' : 'The address works: ${cat.songs.length} songs in the cloud.', good: true);
      });

  Future<void> _testKeys() => _act((c) async {
        final n = await ref.read(cloudServiceFactoryProvider)(c).testKeys();
        _say('The keys work. The bucket holds $n song${n == 1 ? '' : 's'}.', good: true);
      }, writing: true);

  Future<void> _forgetKeys() async {
    await ref.read(cloudConfigStoreProvider).clearKeys();
    ref.invalidate(cloudConfigProvider);
    _keyId.clear();
    _secret.clear();
    _say('The keys are forgotten. This phone can still browse and play.', good: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Library')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Your own songs, stored in your own Cloudflare R2 bucket, and played from there. '
                    'Only upload songs you own or may share.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text('To browse and play', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Every phone that should see the Cloud Library needs just the public address.', style: muted),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('cloud-url'),
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Public address of the bucket',
                      hintText: 'https://pub-xxxxxxxx.r2.dev',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('To upload and delete', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Only the phone you upload from needs these. They stay on this phone: never in a backup, '
                    'never in the app\'s code, and only sent to Cloudflare. Anyone who can use this phone could use '
                    'them, so give the key access to this one bucket only (in Cloudflare: R2 > Manage API tokens).',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('cloud-account'),
                    controller: _account,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Account id',
                      hintText: '32 letters and digits, or paste the S3 address',
                      helperText: 'Paste the "S3 API" address from Cloudflare (https://<id>.r2.cloudflarestorage.com/<bucket>): the id and bucket are taken from it.',
                    ),
                  ),
                  TextField(
                    key: const Key('cloud-bucket'),
                    controller: _bucket,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Bucket name', hintText: 'remotetunes'),
                  ),
                  TextField(
                    key: const Key('cloud-key-id'),
                    controller: _keyId,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Access key id'),
                  ),
                  TextField(
                    key: const Key('cloud-secret'),
                    controller: _secret,
                    autocorrect: false,
                    obscureText: !_showSecret,
                    decoration: InputDecoration(
                      labelText: 'Secret access key',
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? 'Hide' : 'Show',
                        icon: Icon(_showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showSecret = !_showSecret),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(key: const Key('cloud-save'), onPressed: _busy ? null : _save, child: const Text('Save')),
                      OutlinedButton(key: const Key('cloud-test-public'), onPressed: _busy ? null : _testPublic, child: const Text('Test the address')),
                      OutlinedButton(key: const Key('cloud-test-keys'), onPressed: _busy ? null : _testKeys, child: const Text('Test the keys')),
                      TextButton(key: const Key('cloud-forget-keys'), onPressed: _busy ? null : _forgetKeys, child: const Text('Forget the keys')),
                    ],
                  ),
                  if (_busy)
                    const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _message!,
                        key: const Key('cloud-message'),
                        style: TextStyle(color: _good ? theme.colorScheme.primary : theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
