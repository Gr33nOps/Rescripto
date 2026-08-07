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
      children: [
        _SectionLabel(label: 'Intensity'),
        const SizedBox(height: 6),
        SegmentedButton<RewriteIntensity>(
          segments: RewriteIntensity.values
              .map((v) => ButtonSegment(value: v, label: Text(v.label)))
              .toList(),
          selected: {intensity},
          onSelectionChanged: (s) => onIntensityChanged(s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 18),
        _SectionLabel(label: 'Length'),
        const SizedBox(height: 6),
        SegmentedButton<RewriteLength>(
          segments: RewriteLength.values
              .map((v) => ButtonSegment(value: v, label: Text(v.label)))
              .toList(),
          selected: {length},
          onSelectionChanged: (s) => onLengthChanged(s.first),
          showSelectedIcon: false,
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
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
