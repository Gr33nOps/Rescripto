import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../state/settings_controller.dart';

/// App settings: theme, engine tuning, speech model.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _SectionTitle('Appearance'),
            Card(
              child: RadioGroup<String>(
                groupValue: settings.themeMode,
                onChanged: (v) =>
                    settings.setThemeMode(v ?? settings.themeMode),
                child: Column(
                  children: [
                    _RadioTile(
                      icon: Icons.brightness_auto_outlined,
                      label: 'Follow system',
                      value: 'system',
                    ),
                    _RadioTile(
                      icon: Icons.light_mode_outlined,
                      label: 'Light',
                      value: 'light',
                    ),
                    _RadioTile(
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark',
                      value: 'dark',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('AI engine'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.speed_outlined),
                    title: const Text('GPU acceleration'),
                    subtitle: const Text(
                      'Much faster on supported phones (Metal / Vulkan).',
                    ),
                    value: settings.useGpu,
                    onChanged: settings.setUseGpu,
                  ),
                  const Divider(height: 1),
                  _SliderTile(
                    icon: Icons.memory_outlined,
                    label: 'CPU threads',
                    value: settings.threads.toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    display: '${settings.threads}',
                    onChanged: (v) => settings.setThreads(v.round()),
                  ),
                  const Divider(height: 1),
                  _SliderTile(
                    icon: Icons.view_agenda_outlined,
                    label: 'Context size',
                    value: settings.contextSize.toDouble(),
                    min: 2048,
                    max: 8192,
                    divisions: 3,
                    display: '${settings.contextSize} tokens',
                    onChanged: (v) => settings.setContextSize(v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Voice input'),
            Card(
              child: RadioGroup<String>(
                groupValue: settings.whisperModel,
                onChanged: (v) =>
                    settings.setWhisperModel(v ?? settings.whisperModel),
                child: Column(
                  children: [
                    for (final m in const [
                      ('tiny', 'Fastest, multilingual (74 MB)'),
                      ('base', 'Fast, multilingual (141 MB)'),
                      ('small', 'Recommended, multilingual (465 MB)'),
                      ('medium', 'Accurate, multilingual (1.43 GB)'),
                      ('large', 'Best quality, multilingual (2.88 GB)'),
                    ])
                      _RadioTile(
                        icon: Icons.record_voice_over_outlined,
                        label: m.$1,
                        subtitle: m.$2,
                        value: m.$1,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Voice model downloads automatically the first time you '
                        'dictate. Android is currently supported.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('About'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.tagline}\n${AppConstants.privacyPromise}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No accounts, ads, tracking, or cloud processing. Your text '
                      'and recordings stay on this device. AI and voice model files '
                      'are downloaded from Hugging Face when you choose to use them.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Radio<String>(value: value),
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged.call(value),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      display,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
