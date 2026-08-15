import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_messenger.dart';
import '../../core/icon_catalog.dart';
import '../../engine/generation_options.dart';
import '../../models/tone_preset.dart';
import '../../models/ui_mode.dart';
import '../../services/config_store.dart';
import '../../services/routing/target_router.dart';
import '../../state/settings_controller.dart';

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
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _instructionController = TextEditingController(
    text: widget.existing?.instruction ?? '',
  );
  late double _temperature = widget.existing?.temperature ?? 0.5;
  late String _iconToken =
      widget.existing?.iconToken ?? IconCatalog.tokens.first;
  late double _topP = widget.existing?.topP ?? 0.95;
  late int _topK = widget.existing?.topK ?? 40;
  late double _repeatPenalty = widget.existing?.repeatPenalty ?? 1.1;
  late int _maxOutputTokens = widget.existing?.maxOutputTokens ?? 1024;
  late final List<String> _stopSequences = List.of(
    widget.existing?.stopSequences ?? const [],
  );
  final _stopSequenceController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _instructionController.dispose();
    _stopSequenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isNew = existing == null;
    final scheme = Theme.of(context).colorScheme;
    final isPro = context.watch<SettingsController>().uiMode == UiMode.pro;
    // Wherever a rewrite would route to right now, so the advanced section
    // can grey out a field the target won't actually read — see
    // `GenerationFieldSupport`'s own doc for the ground truth this reflects.
    final targetEngineId = context
        .read<TargetRouter>()
        .route(inputLength: 0)
        .target
        ?.engineId;
    final fieldSupport = GenerationFieldSupport.forEngine(targetEngineId ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New tone' : 'Edit tone'),
        actions: [
          if (!isNew)
            Semantics(
              identifier: 'tone_editor_delete',
              child: IconButton(
                tooltip: existing.isBuiltin ? 'Remove' : 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, existing),
              ),
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
                        'This tone comes with Rescripto. If you edit it, future '
                        'updates will not replace your version. Use "Reset to '
                        'default" whenever you want the latest built-in version.',
                        style: TextStyle(
                          color: scheme.onTertiaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              identifier: 'tone_editor_name',
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: 'tone_editor_description',
              child: TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Short description',
                  hintText: 'Shown under the name in the tone list',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: 'tone_editor_instruction',
              child: TextField(
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
            ),
            const SizedBox(height: 20),
            Text('Creativity', style: Theme.of(context).textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: 'tone_editor_temperature',
                    child: Slider(
                      value: _temperature,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      label: _temperature.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    _temperature.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            Text(
              'Predictable ←──────────── Creative',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (isPro) ...[
              const SizedBox(height: 24),
              Text(
                'Advanced generation',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'These controls change how the selected engine writes in this '
                'tone. Controls that do not apply are disabled.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'tone_editor_top_p',
                child: _GenerationSlider(
                  label: 'Top-P',
                  value: _topP,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  display: _topP.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _topP = v),
                ),
              ),
              Semantics(
                identifier: 'tone_editor_top_k',
                child: _GenerationSlider(
                  label: 'Top-K',
                  value: _topK.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  display: '$_topK',
                  enabled: fieldSupport.topK,
                  onChanged: (v) => setState(() => _topK = v.round()),
                ),
              ),
              Semantics(
                identifier: 'tone_editor_repeat_penalty',
                child: _GenerationSlider(
                  label: 'Repeat penalty',
                  value: _repeatPenalty,
                  min: 1,
                  max: 2,
                  divisions: 20,
                  display: _repeatPenalty.toStringAsFixed(2),
                  enabled: fieldSupport.repeatPenalty,
                  onChanged: (v) => setState(() => _repeatPenalty = v),
                ),
              ),
              Semantics(
                identifier: 'tone_editor_max_tokens',
                child: _GenerationSlider(
                  label: 'Max output tokens',
                  value: _maxOutputTokens.toDouble(),
                  min: 128,
                  max: 4096,
                  divisions: 31,
                  display: '$_maxOutputTokens',
                  onChanged: (v) =>
                      setState(() => _maxOutputTokens = v.round()),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Stop sequences',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sequence in _stopSequences)
                    Semantics(
                      identifier: 'tone_editor_stop_sequence_$sequence',
                      child: InputChip(
                        label: Text(sequence),
                        onDeleted: () =>
                            setState(() => _stopSequences.remove(sequence)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'tone_editor_stop_sequence_input',
                      child: TextField(
                        controller: _stopSequenceController,
                        decoration: const InputDecoration(
                          hintText: 'Add a stop sequence',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addStopSequence(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'tone_editor_add_stop_sequence',
                    child: IconButton.filledTonal(
                      onPressed: _addStopSequence,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _IconPicker(
              selected: _iconToken,
              onSelected: (token) => setState(() => _iconToken = token),
            ),
            const SizedBox(height: 24),
            Semantics(
              identifier: 'tone_editor_save',
              child: FilledButton.icon(
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
            ),
            if (!isNew && existing.isBuiltin) ...[
              const SizedBox(height: 12),
              Semantics(
                identifier: 'tone_editor_reset',
                child: OutlinedButton.icon(
                  onPressed: () => _resetToDefault(context, existing.id),
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Reset to default'),
                ),
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
      showAppSnackBar('Give this tone a name first.');
      return;
    }
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) {
      showAppSnackBar(
        'Add an instruction so the model knows how to write this tone.',
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
        topP: _topP,
        topK: _topK,
        repeatPenalty: _repeatPenalty,
        maxOutputTokens: _maxOutputTokens,
        stopSequences: _stopSequences,
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
        title: Text(
          existing.isBuiltin
              ? 'Remove ${existing.name}?'
              : 'Delete ${existing.name}?',
        ),
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
          Semantics(
            identifier: 'tone_editor_delete_confirm',
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(existing.isBuiltin ? 'Remove' : 'Delete'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ConfigStore>().hideTone(existing.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  void _addStopSequence() {
    final value = _stopSequenceController.text.trim();
    if (value.isEmpty || _stopSequences.contains(value)) return;
    setState(() {
      _stopSequences.add(value);
      _stopSequenceController.clear();
    });
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

/// One labelled slider row in the "Advanced generation" section.
/// [enabled] false greys it out rather than hiding it — the value is still
/// saved either way, since a target that ignores the field today might not
/// tomorrow, but it can't be dragged while the current target won't read it.
class _GenerationSlider extends StatelessWidget {
  const _GenerationSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled
        ? null
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPicker extends StatefulWidget {
  const _IconPicker({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = IconCatalog.tokens.toList();
    final visible = _showAll ? tokens : tokens.take(16).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final token in visible)
              Semantics(
                identifier: 'tone_editor_icon_$token',
                label: token.replaceAll('_', ' '),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => widget.onSelected(token),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: token == widget.selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHigh,
                    child: Icon(
                      IconCatalog.resolve(token),
                      color: token == widget.selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (tokens.length > 16)
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Show fewer icons' : 'More icons'),
          ),
      ],
    );
  }
}
