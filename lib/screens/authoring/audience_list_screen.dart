import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/audience_tag.dart';
import '../../services/config_store.dart';
import 'audience_editor_screen.dart';

/// Manage audiences: reorder, edit, remove, add, and bring back a hidden
/// built-in. Mirrors `tone_list_screen.dart`.
class AudienceListScreen extends StatefulWidget {
  const AudienceListScreen({super.key});

  @override
  State<AudienceListScreen> createState() => _AudienceListScreenState();
}

class _AudienceListScreenState extends State<AudienceListScreen> {
  late Future<List<AudienceTag>> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = context.read<ConfigStore>().hiddenAudiences();
  }

  void _refreshHidden() {
    setState(() => _hidden = context.read<ConfigStore>().hiddenAudiences());
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConfigStore>();
    final audiences = store.audiences;

    return Scaffold(
      appBar: AppBar(title: const Text('Audiences')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New audience'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (oldIndex, newIndex) =>
                  _reorder(context, audiences, oldIndex, newIndex),
              children: [
                for (final audience in audiences)
                  Padding(
                    key: ValueKey(audience.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(audience.label),
                        trailing: const Icon(Icons.drag_handle),
                        onTap: () => _openEditor(context, audience),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _HiddenAudiencesSection(hidden: _hidden, onRestored: _refreshHidden),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, AudienceTag? audience) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AudienceEditorScreen(existing: audience)),
    );
    _refreshHidden();
  }

  Future<void> _reorder(
    BuildContext context,
    List<AudienceTag> audiences,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = audiences.map((a) => a.id).toList();
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    await context.read<ConfigStore>().reorderAudiences(ids);
  }
}

class _HiddenAudiencesSection extends StatelessWidget {
  const _HiddenAudiencesSection({required this.hidden, required this.onRestored});

  final Future<List<AudienceTag>> hidden;
  final VoidCallback onRestored;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AudienceTag>>(
      future: hidden,
      builder: (context, snapshot) {
        final audiences = snapshot.data ?? const [];
        if (audiences.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          title: Text('Hidden audiences (${audiences.length})'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final audience in audiences)
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(audience.label),
                trailing: TextButton(
                  onPressed: () async {
                    await context.read<ConfigStore>().resetAudienceToDefault(audience.id);
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
