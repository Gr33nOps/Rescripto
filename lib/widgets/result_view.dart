import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/rewrite_result.dart';

/// Displays the rewrite result with original/rewritten toggle,
/// alternatives, copy and share actions.
class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.result});

  final RewriteResult result;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _showOriginal = false;
  int _variantIndex = 0;

  @override
  void didUpdateWidget(covariant ResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _variantIndex = 0;
      _showOriginal = false;
    } else if (_variantIndex >= widget.result.outputs.length) {
      _variantIndex = widget.result.outputs.isEmpty
          ? 0
          : widget.result.outputs.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outputs = widget.result.outputs;
    final selectedIndex = outputs.isEmpty
        ? 0
        : _variantIndex.clamp(0, outputs.length - 1);
    final text = _showOriginal
        ? widget.result.request.sourceText
        : outputs.isEmpty
        ? 'No rewrite output was produced.'
        : outputs[selectedIndex].text;
    final generation = outputs.isEmpty ? null : outputs.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Result',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (outputs.length > 1)
                  SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < outputs.length; i++)
                        ButtonSegment(value: i, label: Text('V${i + 1}')),
                    ],
                    selected: {selectedIndex},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _variantIndex = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Original')),
                    ButtonSegment(value: false, label: Text('Rewrite')),
                  ],
                  selected: {_showOriginal},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      setState(() => _showOriginal = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.5,
                  color: _showOriginal
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!_showOriginal && generation != null) ...[
                  if (generation.tokensGenerated > 0)
                    _StatChip(
                      icon: Icons.bolt,
                      label:
                          '${generation.tokensGenerated} generated tokens total',
                    ),
                  if (generation.generationTimeMs > 0)
                    _StatChip(
                      icon: Icons.timer_outlined,
                      label:
                          '${(generation.generationTimeMs / 1000).toStringAsFixed(1)}s total · '
                          '${generation.tokensPerSecond.toStringAsFixed(1)} tok/s',
                    ),
                ],
                Semantics(
                  label: 'Copy displayed text',
                  child: IconButton(
                    tooltip: 'Copy',
                    onPressed: () => _copy(text),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ),
                Semantics(
                  label: 'Share displayed text',
                  child: IconButton(
                    tooltip: 'Share',
                    onPressed: () => _share(text),
                    icon: const Icon(Icons.share_outlined),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _share(String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Rewritten with Rescripto'),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
