import 'package:flutter/material.dart';

import 'tag_cleanup.dart';
import 'tag_cleanup_service.dart';

/// Shows proposed tag changes, one card each, and applies the ones that are ticked. Nothing is
/// ticked for you except what you choose (*Select all*, or *Select the sure ones*). Pops with true
/// when anything was changed.
class TagReviewScreen extends StatefulWidget {
  const TagReviewScreen({
    super.key,
    required this.title,
    required this.changes,
    required this.service,
    this.canSkip = false,
  });

  final String title;
  final List<TagChange> changes;
  final TagCleanupService service;

  /// Suggestions can be set aside (not offered again); file-name changes just are not ticked.
  final bool canSkip;

  @override
  State<TagReviewScreen> createState() => _TagReviewScreenState();
}

class _TagReviewScreenState extends State<TagReviewScreen> {
  late final List<TagChange> _left = [...widget.changes];
  final Set<int> _picked = {};
  bool _write = true;
  bool _busy = false;
  bool _changed = false;
  int _done = 0;
  int _total = 0;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _apply() async {
    final chosen = [for (final c in _left) if (_picked.contains(c.songId)) c];
    if (chosen.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = chosen.length;
    });
    try {
      final r = await widget.service.apply(
        chosen,
        writeToFile: _write,
        onProgress: (d, t, _) {
          if (mounted) setState(() => _done = d);
        },
      );
      if (!mounted) return;
      setState(() {
        _left.removeWhere((c) => _picked.contains(c.songId));
        _picked.clear();
        _changed = _changed || r.applied > 0;
      });
      final files = !_write
          ? ''
          : r.notAllowed > 0
              ? ' ${r.written} file${r.written == 1 ? '' : 's'} changed; Android refused ${r.notAllowed} '
                  '(turn on All files access in Settings).'
              : r.failed > 0
                  ? ' ${r.written} file${r.written == 1 ? '' : 's'} changed, ${r.failed} could not be.'
                  : ' ${r.written} file${r.written == 1 ? '' : 's'} changed too.';
      _say('Changed ${r.applied} song${r.applied == 1 ? '' : 's'}.$files You can undo this in Tag cleanup.');
    } catch (_) {
      _say("The changes couldn't be applied.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    await widget.service.markSuggestions(ids, 'skipped');
    if (!mounted) return;
    setState(() {
      _left.removeWhere((c) => _picked.contains(c.songId));
      _picked.clear();
      _changed = true;
    });
    _say('Set aside: not offered again.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sure = _left.where((c) => c.high).length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(
          child: _left.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nothing left to review.', textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        'Only empty fields are filled; nothing that is already there is replaced. Tick what '
                        'you want, then Apply. The last batch can be undone.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const Key('review-all'),
                          onPressed: _busy ? null : () => setState(() => _picked.addAll(_left.map((c) => c.songId))),
                          child: Text('Select all (${_left.length})'),
                        ),
                        if (sure > 0)
                          TextButton(
                            key: const Key('review-sure'),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _picked
                                  ..clear()
                                  ..addAll(_left.where((c) => c.high).map((c) => c.songId))),
                            child: Text('Select the sure ones ($sure)'),
                          ),
                        TextButton(
                          key: const Key('review-none'),
                          onPressed: _busy ? null : () => setState(_picked.clear),
                          child: const Text('Select none'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _left.length,
                        itemBuilder: (context, i) {
                          final c = _left[i];
                          return CheckboxListTile(
                            key: ValueKey('change-${c.songId}'),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            value: _picked.contains(c.songId),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => v == true ? _picked.add(c.songId) : _picked.remove(c.songId)),
                            title: Row(
                              children: [
                                Expanded(child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (c.high)
                                  Icon(Icons.verified_rounded, size: 16, color: theme.colorScheme.primary),
                              ],
                            ),
                            subtitle: Text(c.lines.join('\n')),
                          );
                        },
                      ),
                    ),
                    if (_busy) LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                    CheckboxListTile(
                      key: const Key('review-write'),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Also write into the music files'),
                      subtitle: const Text('Android may refuse unless All files access is on'),
                      value: _write,
                      onChanged: _busy ? null : (v) => setState(() => _write = v ?? true),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          if (widget.canSkip)
                            OutlinedButton(
                              key: const Key('review-skip'),
                              onPressed: _busy || _picked.isEmpty ? null : _skip,
                              child: const Text('Set aside'),
                            ),
                          const Spacer(),
                          FilledButton(
                            key: const Key('review-apply'),
                            onPressed: _busy || _picked.isEmpty ? null : _apply,
                            child: Text('Apply${_picked.isEmpty ? '' : ' (${_picked.length})'}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
