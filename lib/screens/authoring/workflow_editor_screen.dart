import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/engine_target.dart';
import '../../models/rewrite_request.dart';
import '../../models/workflow_definition.dart';
import '../../models/workflow_step.dart';
import '../../services/config_store.dart';
import '../../services/routing/target_router.dart';
import '../../services/settings_service.dart';
import '../../services/workflows/workflow_registry.dart';
import '../../widgets/rewrite_controls.dart';
import '../../widgets/tone_selector.dart';

/// Create or edit a workflow: its name and ordered steps.
///
/// Each step's target engine/model is captured automatically from wherever
/// the app is currently routing a rewrite to when the step is added — see
/// `WorkflowStep`'s own doc for why this screen doesn't also expose a
/// per-step engine/model picker.
class WorkflowEditorScreen extends StatefulWidget {
  const WorkflowEditorScreen({super.key, this.existing});

  /// Null when creating a new workflow.
  final WorkflowDefinition? existing;

  @override
  State<WorkflowEditorScreen> createState() => _WorkflowEditorScreenState();
}

class _WorkflowEditorScreenState extends State<WorkflowEditorScreen> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final List<WorkflowStep> _steps = List.of(widget.existing?.steps ?? const []);
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isNew = existing == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New workflow' : 'Edit workflow'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, existing),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStep(context),
        icon: const Icon(Icons.add),
        label: const Text('Add step'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Workflow name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Steps', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Each step\'s output becomes the next step\'s input.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (_steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No steps yet. Tap "Add step" to start.')),
              )
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final step = _steps.removeAt(oldIndex);
                    _steps.insert(newIndex, step);
                  });
                },
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    _StepTile(
                      key: ValueKey(_steps[i].id),
                      index: i,
                      step: _steps[i],
                      onTap: () => _editStep(context, i),
                      onDelete: () => setState(() => _steps.removeAt(i)),
                    ),
                ],
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
              label: Text(isNew ? 'Create workflow' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addStep(BuildContext context) async {
    final registry = context.read<WorkflowRegistry>();
    final settings = context.read<SettingsService>();
    final router = context.read<TargetRouter>();
    // Falls back to the local engine directly if nothing is currently
    // routable (e.g. no model installed yet) — a step still needs *some*
    // target to be well-formed, and the user can always edit it once
    // something is set up, the same way any other unready target surfaces.
    final target = router.route(inputLength: 0).target ??
        EngineTarget(engineId: 'local.llama', modelRef: settings.selectedModelId);

    final step = await showModalBottomSheet<WorkflowStep>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _StepEditorSheet(
        initial: WorkflowStep(
          id: registry.newStepId(),
          toneId: 'professional',
          intensity: RewriteIntensity.moderate,
          length: RewriteLength.same,
          target: target,
        ),
      ),
    );
    if (step != null) setState(() => _steps.add(step));
  }

  Future<void> _editStep(BuildContext context, int index) async {
    final step = await showModalBottomSheet<WorkflowStep>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _StepEditorSheet(initial: _steps[index]),
    );
    if (step != null) setState(() => _steps[index] = step);
  }

  Future<void> _save(BuildContext context) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give this workflow a name first.')));
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one step first.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final registry = context.read<WorkflowRegistry>();
      final existing = widget.existing;
      final now = DateTime.now();
      final workflow = WorkflowDefinition(
        id: existing?.id ?? registry.newId(),
        name: name,
        steps: _steps,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await registry.save(workflow);
      if (context.mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WorkflowDefinition existing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${existing.name}"?'),
        content: const Text('This permanently deletes the workflow and its steps.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<WorkflowRegistry>().delete(existing.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final WorkflowStep step;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = context.watch<ConfigStore>().toneById(step.toneId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(tone.name),
          subtitle: Text('${step.intensity.label} · ${step.length.label}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
              const Icon(Icons.drag_handle),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _StepEditorSheet extends StatefulWidget {
  const _StepEditorSheet({required this.initial});

  final WorkflowStep initial;

  @override
  State<_StepEditorSheet> createState() => _StepEditorSheetState();
}

class _StepEditorSheetState extends State<_StepEditorSheet> {
  late String _toneId = widget.initial.toneId;
  late RewriteIntensity _intensity = widget.initial.intensity;
  late RewriteLength _length = widget.initial.length;
  late final List<String> _audience = List.of(widget.initial.audience);
  late final _instructionController = TextEditingController(
    text: widget.initial.customInstruction,
  );

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audiences = context.watch<ConfigStore>().audiences;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Step', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Tone', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ToneSelector(
              selectedId: _toneId,
              onChanged: (id) => setState(() => _toneId = id),
            ),
            const SizedBox(height: 20),
            RewriteControls(
              intensity: _intensity,
              length: _length,
              onIntensityChanged: (v) => setState(() => _intensity = v),
              onLengthChanged: (v) => setState(() => _length = v),
            ),
            const SizedBox(height: 20),
            Text('Audience', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final audience in audiences)
                  FilterChip(
                    label: Text(audience.label),
                    selected: _audience.contains(audience.id),
                    onSelected: (_) => setState(() {
                      if (_audience.contains(audience.id)) {
                        _audience.remove(audience.id);
                      } else {
                        _audience.add(audience.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _instructionController,
              decoration: const InputDecoration(
                labelText: 'Extra instructions (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                widget.initial.copyWith(
                  toneId: _toneId,
                  intensity: _intensity,
                  length: _length,
                  audience: _audience,
                  customInstruction: _instructionController.text.trim(),
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
