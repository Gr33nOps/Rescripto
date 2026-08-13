import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/icon_catalog.dart';
import '../services/config_store.dart';

/// Horizontal scrolling selector of tone presets.
///
/// Fades the trailing edge and shows a chevron whenever there are more
/// tones scrolled off-screen — without this, a chip sliced at the screen
/// edge gives no hint that swiping reveals more.
class ToneSelector extends StatefulWidget {
  const ToneSelector({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  State<ToneSelector> createState() => _ToneSelectorState();
}

class _ToneSelectorState extends State<ToneSelector> {
  final _scrollController = ScrollController();
  bool _hasMoreToScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateOverflow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateOverflow);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateOverflow() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final hasMore = position.maxScrollExtent - position.pixels > 1;
    if (hasMore != _hasMoreToScroll) {
      setState(() => _hasMoreToScroll = hasMore);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = context.watch<ConfigStore>().tones;
    // Re-check after the tone list itself changes size (e.g. reordering).
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());

    return Semantics(
      container: true,
      identifier: 'tone_selector',
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: const [Colors.transparent, Colors.black, Colors.black],
                stops: _hasMoreToScroll ? const [0.0, 0.08, 1.0] : const [0.0, 0.0, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 28),
                itemCount: tones.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tone = tones[index];
                  final selected = tone.id == widget.selectedId;
                  return Semantics(
                    identifier: 'tone_option_${tone.id}',
                    child: ChoiceChip(
                      showCheckmark: false,
                      selected: selected,
                      onSelected: (_) => widget.onChanged(tone.id),
                      avatar: Icon(IconCatalog.resolve(tone.iconToken), size: 18),
                      label: Text(tone.name),
                      selectedColor: scheme.primaryContainer,
                      labelStyle: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_hasMoreToScroll)
              IgnorePointer(
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
