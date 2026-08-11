import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icon_catalog.dart';
import '../../models/tone_preset.dart';
import '../../services/config_store.dart';

/// Create or edit one tone preset.
///
/// Fields map 1:1 to [TonePreset]. The icon picker is exactly what
/// [IconCatalog.tokens] was built for — its own doc comment named this
/// screen as the reason it exists, before this screen did.
class ToneEditorScreen extends StatefulWidget {
  const ToneEditorScreen({super.key, this.existing});

  /// Null when creating a new tone.
  final TonePreset? existing;

  @override
  State<ToneEditorScreen> createState() => _ToneEditorScreenState();
}

class _ToneEditorScreenState extends State<ToneEditorScreen> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _instructionController = TextEditingController(
    text: widget.existing?.instruction ?? '',
  );
  late double _temperature = widget.existing?.temperature ?? 0.5;
  late String _iconToken = widget.existing?.iconToken ?? IconCatalog.tokens.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isNew = existing == null;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New tone' : 'Edit tone'),
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
                        'This is a built-in tone. Saving any change detaches it '
                        'from future app updates to its wording — a later '
                        'release that improves "${existing.name}" won\'t reach '
                        'your edited copy. "Reset to default" always undoes this.',
                        style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Short description',
                hintText: 'Shown under the name in the tone list',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _instructionController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Instruction',
                hintText: 'How should the model rewrite text in this tone?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Temperature', style: Theme.of(context).textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _temperature,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _temperature = v),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(_temperature.toStringAsFixed(2), textAlign: TextAlign.end),
                ),
              ],
            ),
            Text(
              'Lower is more predictable, higher is more varied.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _IconPicker(
              selected: _iconToken,
              onSelected: (token) => setState(() => _iconToken = token),
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
              label: Text(isNew ? 'Create tone' : 'Save'),
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give this tone a name first.')));
      return;
    }
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An instruction is required — it\'s what the model reads.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final tone = TonePreset(
        id: existing?.id ?? _generateId(name),
        name: name,
        iconToken: _iconToken,
        description: _descriptionController.text.trim(),
        instruction: instruction,
        temperature: _temperature,
        isBuiltin: existing?.isBuiltin ?? false,
      );
      await context.read<ConfigStore>().upsertTone(tone);
      if (context.mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault(BuildContext context, String id) async {
    await context.read<ConfigStore>().resetToneToDefault(id);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(BuildContext context, TonePreset existing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing.isBuiltin ? 'Remove ${existing.name}?' : 'Delete ${existing.name}?'),
        content: Text(
          existing.isBuiltin
              ? 'This built-in tone will be hidden from the tone list. You '
                    'can bring it back later from "Hidden tones" at the '
                    'bottom of the tone list.'
              : 'This tone will be permanently deleted.',
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
    await context.read<ConfigStore>().hideTone(existing.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  String _generateId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'user_${slug.isEmpty ? 'tone' : slug}_$suffix';
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final token in IconCatalog.tokens)
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onSelected(token),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: token == selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              child: Icon(
                IconCatalog.resolve(token),
                color: token == selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
