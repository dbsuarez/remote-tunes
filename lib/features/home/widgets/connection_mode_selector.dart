import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';

/// Auto / Local only / Online only selector. Persisted via [onChanged].
class ConnectionModeSelector extends StatelessWidget {
  const ConnectionModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ConnectionMode value;
  final ValueChanged<ConnectionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ConnectionMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in ConnectionMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
