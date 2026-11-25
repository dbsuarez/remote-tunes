import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/theme/skin.dart';
import '../../providers/providers.dart';

/// Pick a skin, add one by pasting its JSON, copy one to share, remove one.
class SkinScreen extends ConsumerWidget {
  const SkinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final repo = ref.read(settingsRepositoryProvider);
    final current = settings?.skinId ?? Skin.defaultId;
    final custom = settings?.customSkins ?? const <Skin>[];
    final all = [...Skin.builtIns, ...custom];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skins'),
        actions: [
          IconButton(
            tooltip: 'Add a skin',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _addDialog(context, ref, custom),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'A skin changes the colors behind the screens and the accent used when a song '
              'has no cover color. Covers still tint the player.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final s in all)
              _SkinTile(
                skin: s,
                selected: s.id == current,
                onTap: () {
                  Haptics.selection();
                  repo.setSkinId(s.id);
                },
                onCopy: () async {
                  await Clipboard.setData(ClipboardData(text: s.toJson()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text('Copied "${s.name}" to share')));
                  }
                },
                onRemove: s.builtIn
                    ? null
                    : () async {
                        await repo.setCustomSkins([for (final c in custom) if (c.id != s.id) c]);
                        if (current == s.id) await repo.setSkinId(Skin.defaultId);
                      },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref, List<Skin> custom) async {
    final repo = ref.read(settingsRepositoryProvider);
    final text = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add a skin'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Paste the skin\'s JSON (copy one with the copy button to see the format).'),
                const SizedBox(height: 8),
                TextField(
                  controller: text,
                  maxLines: 8,
                  minLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(errorText: error, hintText: '{"name": "My skin", ...}'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) setState(() => text.text = d!.text!);
                  },
                  icon: const Icon(Icons.paste_rounded),
                  label: const Text('Paste'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final skin = Skin.parse(text.text);
                  if (Skin.builtIns.any((b) => b.id == skin.id)) {
                    throw const SkinException('That name is used by a built-in skin. Pick another.');
                  }
                  await repo.setCustomSkins([for (final c in custom) if (c.id != skin.id) c, skin]);
                  await repo.setSkinId(skin.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on SkinException catch (e) {
                  setState(() => error = e.message);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
  }
}

class _SkinTile extends StatelessWidget {
  const _SkinTile({
    required this.skin,
    required this.selected,
    required this.onTap,
    required this.onCopy,
    this.onRemove,
  });

  final Skin skin;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(skin.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: skin.background,
            borderRadius: BorderRadius.circular(skin.cardRadius),
            border: Border.all(
              color: selected ? skin.primary : skin.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // A little preview: surface, raised surface, accent, second accent.
              for (final c in [skin.surface, skin.surfaceHigh, skin.primary, skin.secondary])
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: skin.outline),
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  skin.name,
                  style: TextStyle(
                    color: skin.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: skin.primary),
              IconButton(
                tooltip: 'Copy ${skin.name} to share',
                icon: Icon(Icons.copy_rounded, color: skin.secondary, size: 20),
                onPressed: onCopy,
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove ${skin.name}',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.white70),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
