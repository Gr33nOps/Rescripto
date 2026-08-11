import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/icon_catalog.dart';
import '../services/config_store.dart';

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
    final tones = context.watch<ConfigStore>().tones;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: tones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tone = tones[index];
          final selected = tone.id == selectedId;
          return ChoiceChip(
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => onChanged(tone.id),
            avatar: Icon(IconCatalog.resolve(tone.iconToken), size: 18),
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
