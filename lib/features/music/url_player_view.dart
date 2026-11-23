import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/url_validation.dart';
import '../../providers/recent_links.dart';
import 'music_source.dart';

/// "Play a link" form: paste an internet audio URL, play it, and replay recent
/// links. Used on the Player (plays directly) and on the Controller (sends the
/// link to the Player), through [onPlay].
class UrlPlayerView extends ConsumerStatefulWidget {
  const UrlPlayerView({
    super.key,
    required this.onPlay,
    this.enabled = true,
    this.target = 'this phone',
    this.initialUrl = '',
  });

  /// Pre-fills the link box (the apps pass a known-good test MP3).
  final String initialUrl;

  /// Plays the link. Throw a [PlaybackException]/[ControllerException] with a
  /// readable message on failure; the form shows it.
  final Future<void> Function(String url, String? title) onPlay;

  /// False disables the form (e.g. while the Controller is reconnecting).
  final bool enabled;

  /// Wording for where the audio will play ("the Player").
  final String target;

  @override
  ConsumerState<UrlPlayerView> createState() => _UrlPlayerViewState();
}

class _UrlPlayerViewState extends ConsumerState<UrlPlayerView> {
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl);
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) {
      setState(() {
        _url.text = text;
        _error = null;
      });
    }
  }

  Future<void> _play(String rawUrl, {String? title}) async {
    final check = validateAudioUrl(rawUrl);
    if (!check.isValid) {
      setState(() => _error = check.error);
      return;
    }
    final url = check.uri!.toString();
    final name = (title ?? _name.text).trim();

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPlay(url, name.isEmpty ? null : name);
      await ref
          .read(recentLinksStoreProvider)
          .remember(url, title: name.isEmpty ? null : name);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Playing on ${widget.target}')),
          );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentLinksProvider).valueOrNull ?? const <RecentLink>[];
    final locked = _busy || !widget.enabled;

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              color: theme.colorScheme.secondary.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.public_rounded, color: theme.colorScheme.secondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Internet audio plays on ${widget.target}, so it needs an '
                        'internet connection (Wi‑Fi or mobile data) and may use '
                        'data. Music saved on the phone keeps working offline.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !locked,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                // Rebuild so the "pre-filled" note disappears once edited.
                setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Link to an audio file',
                hintText: 'https://example.com/song.mp3',
                errorText: _error,
                errorMaxLines: 4,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: locked ? null : _paste,
                ),
              ),
            ),
            if (widget.initialUrl.isNotEmpty &&
                _url.text == widget.initialUrl) ...[
              const SizedBox(height: 6),
              Text(
                'Pre-filled with a test MP3 (60 seconds) so you can try this '
                'right away. Replace it with your own link any time.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !locked,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _play(_url.text),
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: locked ? null : () => _play(_url.text),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_busy ? 'Checking the link…' : 'Play'),
            ),
            const SizedBox(height: 8),
            Text(
              'Use a direct link to an audio file (for example ending in .mp3). '
              'Links to web pages, such as streaming-app or video pages, will not work.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (recents.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Recent links', style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: locked
                        ? null
                        : () => ref.read(recentLinksStoreProvider).clear(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              Card(
                child: Column(
                  children: [
                    for (final r in recents)
                      ListTile(
                        minTileHeight: 64,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          r.title ?? titleFromUrl(Uri.parse(r.url)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(r.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        enabled: !locked,
                        onTap: () {
                          _url.text = r.url;
                          _name.text = r.title ?? '';
                          _play(r.url, title: r.title);
                        },
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: locked
                              ? null
                              : () => ref
                                  .read(recentLinksStoreProvider)
                                  .remove(r.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
