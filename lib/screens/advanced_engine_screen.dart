import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import '../widgets/settings_tiles.dart';

/// The on-device engine controls (CPU threads, context size), split out from
/// the main Settings screen because most people never change them.
///
/// There is no GPU switch. The native engine is built CPU-only: the ggml
/// Vulkan backend needs loader symbols Android 7 lacks, and the catalog's
/// 1B-3B models run as fast or faster on a phone's CPU. The switch that used
/// to be here changed nothing. The stored `use_gpu` value is still read and
/// written so older backups keep importing cleanly.
class AdvancedEngineScreen extends StatelessWidget {
  const AdvancedEngineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'These affect on-device rewriting only. The defaults suit most '
              'phones.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const SectionTitle('On-device engine'),
            Card(
              child: Column(
                children: [
                  Semantics(
                    identifier: 'threads_slider',
                    child: SliderTile(
                      icon: Icons.memory_outlined,
                      label: 'CPU threads',
                      value: settings.threads.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      display: '${settings.threads}',
                      onChanged: (v) => settings.setThreads(v.round()),
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    identifier: 'context_size_slider',
                    child: SliderTile(
                      icon: Icons.view_agenda_outlined,
                      label: 'Context size',
                      value: settings.contextSize.toDouble(),
                      min: 2048,
                      max: 8192,
                      divisions: 3,
                      display: '${settings.contextSize} tokens',
                      onChanged: (v) => settings.setContextSize(v.round()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  settings.setThreads(4);
                  settings.setContextSize(2048);
                },
                icon: const Icon(Icons.restore),
                label: const Text('Reset to defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
