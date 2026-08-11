import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icon_catalog.dart';
import '../../models/tone_preset.dart';
import '../../services/config_store.dart';
import 'tone_editor_screen.dart';

/// Manage tones: reorder, edit, remove, add, and bring back a hidden
/// built-in.
class ToneListScreen extends StatefulWidget {
  const ToneListScreen({super.key});

  @override
  State<ToneListScreen> createState() => _ToneListScreenState();
}

class _ToneListScreenState extends State<ToneListScreen> {
  late Future<List<TonePreset>> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = context.read<ConfigStore>().hiddenTones();
  }

  void _refreshHidden() {
    setState(() => _hidden = context.read<ConfigStore>().hiddenTones());
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConfigStore>();
    final tones = store.tones;

    return Scaffold(
      appBar: AppBar(title: const Text('Tones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New tone'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (oldIndex, newIndex) => _reorder(context, tones, oldIndex, newIndex),
              children: [
                for (final tone in tones)
                  Padding(
                    key: ValueKey(tone.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(IconCatalog.resolve(tone.iconToken)),
                        title: Text(tone.name),
                        subtitle: Text(
                          tone.description.isEmpty ? tone.instruction : tone.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.drag_handle),
                        onTap: () => _openEditor(context, tone),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _HiddenTonesSection(hidden: _hidden, onRestored: _refreshHidden),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, TonePreset? tone) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ToneEditorScreen(existing: tone)),
    );
    _refreshHidden();
  }

  Future<void> _reorder(
    BuildContext context,
    List<TonePreset> tones,
    int oldIndex,
    int newIndex,
  ) async {
    // onReorderItem's newIndex already accounts for the removed item at
    // oldIndex, unlike the deprecated onReorder.
    final ids = tones.map((t) => t.id).toList();
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    await context.read<ConfigStore>().reorderTones(ids);
  }
}

class _HiddenTonesSection extends StatelessWidget {
  const _HiddenTonesSection({required this.hidden, required this.onRestored});

  final Future<List<TonePreset>> hidden;
  final VoidCallback onRestored;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TonePreset>>(
      future: hidden,
      builder: (context, snapshot) {
        final tones = snapshot.data ?? const [];
        if (tones.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          title: Text('Hidden tones (${tones.length})'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final tone in tones)
              ListTile(
                leading: Icon(IconCatalog.resolve(tone.iconToken)),
                title: Text(tone.name),
                trailing: TextButton(
                  onPressed: () async {
                    await context.read<ConfigStore>().resetToneToDefault(tone.id);
                    onRestored();
                  },
                  child: const Text('Restore'),
                ),
              ),
          ],
        );
      },
    );
  }
}
