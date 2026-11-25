import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_config_store.dart';
import 'cloud_models.dart';
import 'cloud_pickers.dart';
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

  /// Fills everything from a notes file (the details Cloudflare shows, saved as text). If it has more
  /// than one pair of keys, the first one that Cloudflare accepts is used.
  Future<void> _import() async {
    final String? text;
    try {
      text = await ref.read(cloudNotesPickerProvider)?.call();
    } catch (_) {
      _say("The file couldn't be opened.");
      return;
    }
    if (text == null) return;
    final notes = R2Notes.parse(text);
    if (notes.isEmpty) {
      _say('That file has no Cloudflare R2 details in it (account id, bucket, public address or keys).');
      return;
    }
    setState(() {
      _busy = true;
      _url.text = notes.publicUrl.isNotEmpty ? notes.publicUrl : _url.text;
      _account.text = notes.accountId.isNotEmpty ? notes.accountId : _account.text;
      _bucket.text = notes.bucket.isNotEmpty ? notes.bucket : _bucket.text;
    });
    try {
      if (notes.keys.isEmpty) {
        final c = notes.toConfig();
        await ref.read(cloudConfigStoreProvider).save(_config.copyWith(publicUrl: c.publicUrl.isEmpty ? _config.publicUrl : c.publicUrl));
        ref.invalidate(cloudConfigProvider);
        _say('Filled in the address, account and bucket. There were no keys in that file.', good: true);
        return;
      }
      // Try each pair of keys until Cloudflare accepts one.
      String? lastProblem;
      for (var n = 0; n < notes.keys.length; n++) {
        final c = _config.copyWith(accessKeyId: notes.keys[n].id, secretKey: notes.keys[n].secret);
        setState(() {
          _keyId.text = c.accessKeyId;
          _secret.text = c.secretKey;
        });
        final problem = c.problem(forWriting: true);
        if (problem != null) {
          lastProblem = problem;
          continue;
        }
        try {
          final count = await ref.read(cloudServiceFactoryProvider)(c).testKeys();
          await ref.read(cloudConfigStoreProvider).save(c);
          ref.invalidate(cloudConfigProvider);
          final which = notes.keys.length > 1 ? ' (key set ${n + 1} of ${notes.keys.length})' : '';
          _say('Filled in from the file and saved$which. The keys work; the bucket holds $count song${count == 1 ? '' : 's'}.', good: true);
          return;
        } on R2Exception catch (e) {
          lastProblem = e.message;
          if (!e.refused) break; // no internet and the like: another pair would fail the same way
        }
      }
      // Nothing was accepted: what was read stays in the fields so it can be fixed by hand.
      await ref.read(cloudConfigStoreProvider).save(_config);
      ref.invalidate(cloudConfigProvider);
      _say('Filled in from the file, but the keys did not work: ${lastProblem ?? 'unknown problem'}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                  if (ref.watch(cloudNotesPickerProvider) != null) ...[
                    OutlinedButton.icon(
                      key: const Key('cloud-import'),
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import everything from a file'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A text file with the details Cloudflare shows (account id, bucket, public address, access key id and '
                      'secret). Copy it to this phone, pick it here, and the fields are filled in and the keys tried.',
                      style: muted,
                    ),
                    const SizedBox(height: 16),
                  ],
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
                  const SizedBox(height: 24),
                  ExpansionTile(
                    key: const Key('cloud-cors'),
                    tilePadding: EdgeInsets.zero,
                    title: Text('Using it from the web page', style: theme.textTheme.titleMedium),
                    children: [
                      Text(
                        'A web page may only read your bucket if the bucket allows it. In Cloudflare: R2 > your bucket > '
                        'Settings > CORS Policy > Add, and paste this (it names the address of the web Controller). The phone app '
                        'does not need it.',
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(CloudCors.policy(), key: const Key('cloud-cors-text'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('cloud-cors-copy'),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: CloudCors.policy()));
                            _say('Copied.', good: true);
                          },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy'),
                        ),
                      ),
                    ],
                  ),
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
