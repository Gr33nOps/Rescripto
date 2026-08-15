import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_messenger.dart';
import '../models/rewrite_result.dart';

/// Displays the rewrite result with original/rewritten toggle,
/// alternatives, copy and share actions.
///
/// [onVariantSelected] exists because which variant is showing is a decision
/// the *caller* may need to act on, not just render. It shipped as private
/// state, so the rewrite screen's "Insert & return" — the PROCESS_TEXT
/// round-trip — always sent `result.primary.text`, i.e. V1, no matter which
/// variant the user had picked. Copy and Share were never affected; they
/// read the same local text this widget displays.
class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.result, this.onVariantSelected});

  final RewriteResult result;

  /// Called with the newly selected variant index, and once on first build
  /// so a caller never has to assume the initial selection is 0.
  final ValueChanged<int>? onVariantSelected;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _showOriginal = false;
  int _variantIndex = 0;

  @override
  void initState() {
    super.initState();
    _notifySelection(_variantIndex);
  }

  @override
  void didUpdateWidget(covariant ResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _variantIndex = 0;
      _showOriginal = false;
      // A fresh result resets to V1 — the caller has to hear about that, or
      // it would keep acting on the index selected against the old result.
      _notifySelection(0);
    } else if (_variantIndex >= widget.result.outputs.length) {
      _variantIndex = widget.result.outputs.isEmpty
          ? 0
          : widget.result.outputs.length - 1;
      _notifySelection(_variantIndex);
    }
  }

  /// Deferred a frame: both call sites above run during build/lifecycle, and
  /// a parent that responds with `setState` would otherwise be mutating the
  /// tree mid-build.
  void _notifySelection(int index) {
    final callback = widget.onVariantSelected;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(index);
    });
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rewrite result',
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
                  Semantics(
                    identifier: 'variant_selector',
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < outputs.length; i++)
                          ButtonSegment(
                            value: i,
                            label: Semantics(
                              identifier: 'variant_${i + 1}',
                              child: Text('V${i + 1}'),
                            ),
                          ),
                      ],
                      selected: {selectedIndex},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        setState(() => _variantIndex = s.first);
                        _notifySelection(s.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                Semantics(
                  identifier: 'result_view_toggle',
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Semantics(
                          identifier: 'show_original',
                          child: const Text('Original'),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Semantics(
                          identifier: 'show_rewrite',
                          child: const Text('Rewrite'),
                        ),
                      ),
                    ],
                    selected: {_showOriginal},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _showOriginal = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
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
                Semantics(
                  label: 'Copy displayed text',
                  identifier: 'copy_result',
                  child: IconButton(
                    tooltip: 'Copy',
                    onPressed: () => _copy(text),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ),
                Semantics(
                  label: 'Share displayed text',
                  identifier: 'share_result',
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
    showAppSnackBar('Copied to clipboard.');
  }

  Future<void> _share(String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Rewritten with Rescripto'),
    );
  }
}
