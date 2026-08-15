import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import '../widgets/settings_tiles.dart';

/// The technical AI-engine controls (GPU acceleration, CPU threads, context
/// size) — split out from the main Settings screen, which most people set
/// once and then never revisit, so they no longer sit between the
/// once-per-install "Authoring" tiles and the more commonly used
/// "Voice input" / "Privacy & cloud" sections.
class AdvancedEngineScreen extends StatelessWidget {
  const AdvancedEngineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'The recommended defaults work well for most phones. Change '
              'these settings only if you need to tune performance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const SectionTitle('AI engine'),
            Card(
              child: Column(
                children: [
                  Semantics(
                    identifier: 'gpu_acceleration_switch',
                    child: SwitchListTile(
                      secondary: const Icon(Icons.speed_outlined),
                      title: const Text('GPU acceleration'),
                      subtitle: const Text(
                        'Experimental. The first rewrite after opening the app '
                        'takes several extra minutes while your GPU driver '
                        'builds its shaders, and many phones are faster on CPU. '
                        'Leave off unless you have measured a gain.',
                      ),
                      isThreeLine: true,
                      value: settings.useGpu,
                      onChanged: settings.setUseGpu,
                    ),
                  ),
                  const Divider(height: 1),
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
                label: const Text('Reset to recommended defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
