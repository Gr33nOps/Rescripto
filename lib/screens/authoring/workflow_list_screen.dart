import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/workflow_definition.dart';
import '../../services/workflows/workflow_registry.dart';
import '../workflow_run_screen.dart';
import 'workflow_editor_screen.dart';

/// Saved workflows: tap to run, edit icon to change its steps, add new.
class WorkflowListScreen extends StatelessWidget {
  const WorkflowListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final workflows = context.watch<WorkflowRegistry>().workflows;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Workflows')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkflowEditorScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New workflow'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'A workflow chains several rewrite steps: each step\'s '
                      'output becomes the next step\'s input. Only the final '
                      'result is saved to history.',
                      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (workflows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No workflows yet.\nTap "New workflow" to build one.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final workflow in workflows) ...[
                _WorkflowTile(workflow: workflow),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowTile extends StatelessWidget {
  const _WorkflowTile({required this.workflow});

  final WorkflowDefinition workflow;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.route_outlined),
        title: Text(workflow.name),
        subtitle: Text('${workflow.steps.length} step${workflow.steps.length == 1 ? '' : 's'}'),
        trailing: IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => WorkflowEditorScreen(existing: workflow)),
          ),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WorkflowRunScreen(workflow: workflow)),
        ),
      ),
    );
  }
}
