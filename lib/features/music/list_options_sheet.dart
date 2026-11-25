import 'package:flutter/material.dart';

import '../../core/song_list_look.dart';

/// "List options" (for one kind of list): how this kind of list is drawn. A change applies at once and
/// is remembered for every list of the same kind.
Future<void> showListOptions(
  BuildContext context, {
  required String kind,
  required ListLook look,
  required ValueChanged<ListLook> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ListOptionsSheet(kind: kind, look: look, onChanged: onChanged),
  );
}

class ListOptionsSheet extends StatefulWidget {
  const ListOptionsSheet({
    super.key,
    required this.kind,
    required this.look,
    required this.onChanged,
  });

  final String kind;
  final ListLook look;
  final ValueChanged<ListLook> onChanged;

  @override
  State<ListOptionsSheet> createState() => _ListOptionsSheetState();
}

class _ListOptionsSheetState extends State<ListOptionsSheet> {
  late ListLook _look = widget.look;

  void _set(ListLook l) {
    setState(() => _look = l);
    widget.onChanged(l);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('List options: ${listKindLabels[widget.kind] ?? 'Songs'}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Remembered for every list of this kind.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            CheckboxListTile(
              key: const Key('titles-only'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Show titles only'),
              subtitle: const Text('No artist or album line'),
              value: _look.titlesOnly,
              onChanged: (v) => _set(_look.copyWith(titlesOnly: v ?? false)),
            ),
            const SizedBox(height: 4),
            Text('View as', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            RadioGroup<SongListView>(
              groupValue: _look.view,
              onChanged: (v) => _set(_look.copyWith(view: v)),
              child: Column(
                children: [
                  for (final v in SongListView.values)
                    RadioListTile<SongListView>(
                      key: ValueKey('view-${v.name}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: v,
                      title: Text(v.label),
                      subtitle: Text(v.hint),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
