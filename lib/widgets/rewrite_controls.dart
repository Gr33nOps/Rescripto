import 'package:flutter/material.dart';

import '../models/rewrite_request.dart';

/// Intensity + length controls.
class RewriteControls extends StatelessWidget {
  const RewriteControls({
    super.key,
    required this.intensity,
    required this.length,
    required this.onIntensityChanged,
    required this.onLengthChanged,
  });

  final RewriteIntensity intensity;
  final RewriteLength length;
  final ValueChanged<RewriteIntensity> onIntensityChanged;
  final ValueChanged<RewriteLength> onLengthChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: 'Intensity'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            container: true,
            identifier: 'strength_selector',
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in RewriteIntensity.values)
                  Semantics(
                    identifier: 'strength_option_${value.name}',
                    child: ChoiceChip(
                      label: Text(value.label),
                      selected: intensity == value,
                      onSelected: (_) => onIntensityChanged(value),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SectionLabel(label: 'Length'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            container: true,
            identifier: 'length_selector',
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in RewriteLength.values)
                  Semantics(
                    identifier: 'length_option_${value.name}',
                    child: ChoiceChip(
                      label: Text(value.label),
                      selected: length == value,
                      onSelected: (_) => onLengthChanged(value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
