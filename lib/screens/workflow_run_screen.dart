import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messenger.dart';
import '../engine/engine_capabilities.dart';
import '../engine/engine_error_messages.dart';
import '../engine/engine_exception.dart';
import '../engine/engine_stage.dart';
import '../engine/workflow_runner.dart';
import '../models/rewrite_output.dart';
import '../models/rewrite_request.dart';
import '../models/rewrite_result.dart';
import '../models/workflow_definition.dart';
import '../services/config_store.dart';
import '../widgets/result_view.dart';

/// Runs one [WorkflowDefinition] against user-entered text, showing live
/// per-step progress and the final result.
class WorkflowRunScreen extends StatefulWidget {
  const WorkflowRunScreen({super.key, required this.workflow});

  final WorkflowDefinition workflow;

  @override
  State<WorkflowRunScreen> createState() => _WorkflowRunScreenState();
}

class _WorkflowRunScreenState extends State<WorkflowRunScreen> {
  final _textController = TextEditingController();
  String? _finalOutput;
  String? _originalInput;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<WorkflowRunner>();
    final workflow = widget.workflow;

    return Scaffold(
      appBar: AppBar(
        title: Text(workflow.name),
        actions: [
          if (runner.isRunning)
            Semantics(
              identifier: 'workflow_run_cancel',
              child: IconButton(
                tooltip: 'Stop',
                onPressed: runner.isCancelling ? null : runner.cancel,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Semantics(
              identifier: 'workflow_run_input',
              child: TextField(
                controller: _textController,
                enabled: !runner.isRunning,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Text to run through this workflow',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                identifier: 'workflow_run_button',
                child: FilledButton.icon(
                  onPressed: runner.isRunning ? null : () => _run(context),
                  icon: runner.isRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined),
                  label: Text(runner.isRunning ? 'Running…' : 'Run workflow'),
                ),
              ),
            ),
            if (runner.isRunning || runner.currentStepIndex >= 0) ...[
              const SizedBox(height: 20),
              _StepProgress(runner: runner, workflow: workflow),
            ],
            if (_finalOutput != null) ...[
              const SizedBox(height: 16),
              ResultView(
                result: RewriteResult(
                  outputs: [RewriteOutput(text: _finalOutput!)],
                  request: RewriteRequest(
                    sourceText: _originalInput ?? '',
                    toneId: workflow.steps.last.toneId,
                    intensity: workflow.steps.last.intensity,
                    length: workflow.steps.last.length,
                  ),
                  createdAt: DateTime.now(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      showAppSnackBar('Enter some text first.');
      return;
    }
    setState(() {
      _finalOutput = null;
      _originalInput = text;
    });

    final runner = context.read<WorkflowRunner>();
    try {
      final result = await runner.run(widget.workflow, text);
      if (mounted) setState(() => _finalOutput = result);
    } on EngineException catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(describeEngineError(e));
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(
        'Couldn’t finish this workflow. Check its steps and try again.',
      );
    }
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.runner, required this.workflow});

  final WorkflowRunner runner;
  final WorkflowDefinition workflow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final configStore = context.watch<ConfigStore>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < workflow.steps.length; i++) ...[
              _StepRow(
                index: i,
                toneName: configStore.toneById(workflow.steps[i].toneId).name,
                state: i < runner.currentStepIndex
                    ? _StepState.done
                    : i == runner.currentStepIndex
                    ? (runner.isRunning ? _StepState.running : _StepState.done)
                    : _StepState.pending,
                stage: i == runner.currentStepIndex ? runner.stage : null,
                output: i < runner.stepOutputs.length
                    ? runner.stepOutputs[i]
                    : null,
                streamingText: i == runner.currentStepIndex
                    ? runner.currentStreamingText
                    : '',
              ),
              if (i != workflow.steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (runner.lastError != null) ...[
              const SizedBox(height: 8),
              Text(runner.lastError!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

enum _StepState { pending, running, done }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.toneName,
    required this.state,
    required this.stage,
    required this.output,
    required this.streamingText,
  });

  final int index;
  final String toneName;
  final _StepState state;
  final EngineStage? stage;
  final String? output;
  final String streamingText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (state) {
      _StepState.pending => (
        Icons.radio_button_unchecked,
        scheme.onSurfaceVariant,
      ),
      _StepState.running => (Icons.autorenew, scheme.primary),
      _StepState.done => (Icons.check_circle, scheme.primary),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step ${index + 1}: $toneName',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state == _StepState.running)
                Text(
                  stageLabel(
                    stage ?? EngineStage.preparing,
                    const EngineCapabilities(
                      needsLocalInstall: false,
                      requiresNetwork: false,
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (state == _StepState.done && output != null)
                Text(
                  output!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
