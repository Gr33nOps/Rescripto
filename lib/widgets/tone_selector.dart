import 'package:flutter/material.dart';

import '../models/tone_preset.dart';

/// Horizontal scrolling selector of tone presets.
class ToneSelector extends StatelessWidget {
  const ToneSelector({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: ToneLibrary.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tone = ToneLibrary.all[index];
          final selected = tone.id == selectedId;
          return ChoiceChip(
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => onChanged(tone.id),
            avatar: Icon(tone.icon, size: 18),
            label: Text(tone.name),
            selectedColor: scheme.primaryContainer,
            labelStyle: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          );
        },
      ),
    );
  }
}
