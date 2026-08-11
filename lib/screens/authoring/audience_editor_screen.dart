import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/audience_tag.dart';
import '../../services/config_store.dart';

/// Create or edit one audience tag.
///
/// Deliberately does not let the user edit an existing audience's id —
/// only its label. `RewriteRequest.audience` stores ids precisely so a
/// rename here is safe: every existing selection, in every screen that
/// still holds one, keeps pointing at the same row.
class AudienceEditorScreen extends StatefulWidget {
  const AudienceEditorScreen({super.key, this.existing});

  /// Null when creating a new audience.
  final AudienceTag? existing;

  @override
  State<AudienceEditorScreen> createState() => _AudienceEditorScreenState();
}

class _AudienceEditorScreenState extends State<AudienceEditorScreen> {
  late final _labelController = TextEditingController(text: widget.existing?.label ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isNew = existing == null;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New audience' : 'Edit audience'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: existing.isBuiltin ? 'Remove' : 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, existing),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (!isNew && existing.isBuiltin) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This is a built-in audience. Renaming it detaches it '
                        'from future app updates to its wording. "Reset to '
                        'default" always undoes this.',
                        style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _labelController,
              autofocus: isNew,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. coworkers, a teacher, customers',
                helperText: 'Interpolated directly: "Audience: written for <label>."',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(context),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(isNew ? 'Create audience' : 'Save'),
            ),
            if (!isNew && existing.isBuiltin) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _resetToDefault(context, existing.id),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Reset to default'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give this audience a label first.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final audience = AudienceTag(
        id: existing?.id ?? _generateId(label),
        label: label,
        isBuiltin: existing?.isBuiltin ?? false,
      );
      await context.read<ConfigStore>().upsertAudience(audience);
      if (context.mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault(BuildContext context, String id) async {
    await context.read<ConfigStore>().resetAudienceToDefault(id);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(BuildContext context, AudienceTag existing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing.isBuiltin ? 'Remove ${existing.label}?' : 'Delete ${existing.label}?',
        ),
        content: Text(
          existing.isBuiltin
              ? 'This built-in audience will be hidden from the list. You '
                    'can bring it back later from "Hidden audiences" at the '
                    'bottom of the list.'
              : 'This audience will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(existing.isBuiltin ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ConfigStore>().hideAudience(existing.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  String _generateId(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'user_${slug.isEmpty ? 'audience' : slug}_$suffix';
  }
}
