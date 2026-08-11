import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_routes.dart';
import '../core/constants.dart';
import '../models/processing_mode.dart';
import '../models/ui_mode.dart';
import '../state/rewrite_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/settings_tiles.dart';

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
            const SectionTitle('Appearance'),
            Card(
              child: RadioGroup<String>(
                groupValue: settings.themeMode,
                onChanged: (v) =>
                    settings.setThemeMode(v ?? settings.themeMode),
                child: const Column(
                  children: [
                    RadioTile(
                      icon: Icons.brightness_auto_outlined,
                      label: 'Follow system',
                      value: 'system',
                    ),
                    RadioTile(
                      icon: Icons.light_mode_outlined,
                      label: 'Light',
                      value: 'light',
                    ),
                    RadioTile(
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark',
                      value: 'dark',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Processing mode'),
            Card(
              child: RadioGroup<ProcessingMode>(
                groupValue: settings.processingMode,
                onChanged: (mode) => settings.setProcessingMode(mode ?? settings.processingMode),
                child: Column(
                  children: [
                    _ModeRadioTile(
                      icon: Icons.lock_outline,
                      label: 'Local',
                      subtitle: 'Always on-device. Never sends text anywhere.',
                      value: ProcessingMode.local,
                    ),
                    _ModeRadioTile(
                      icon: Icons.cloud_outlined,
                      label: 'Cloud',
                      subtitle: 'Always uses your configured cloud provider.',
                      value: ProcessingMode.cloud,
                    ),
                    _ModeRadioTile(
                      icon: Icons.swap_horiz_outlined,
                      label: 'Hybrid',
                      subtitle: 'Prefers on-device; asks before falling back to cloud.',
                      value: ProcessingMode.hybrid,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Editor'),
            Card(
              child: RadioGroup<UiMode>(
                groupValue: settings.uiMode,
                onChanged: (mode) => _setUiMode(context, mode ?? settings.uiMode),
                child: const Column(
                  children: [
                    _ModeRadioTile(
                      icon: Icons.tune_outlined,
                      label: 'Simple',
                      subtitle: 'Tone and rewrite only.',
                      value: UiMode.simple,
                    ),
                    _ModeRadioTile(
                      icon: Icons.tune,
                      label: 'Pro',
                      subtitle: 'Intensity, length, audience, instructions, and variants.',
                      value: UiMode.pro,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Authoring'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.style_outlined),
                    title: const Text('Tones'),
                    subtitle: const Text('Edit, reorder, add, or remove tone presets'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.tones),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('Audiences'),
                    subtitle: const Text('Edit, reorder, add, or remove audience tags'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.audiences),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('AI engine'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
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
                  const Divider(height: 1),
                  SliderTile(
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
                  SliderTile(
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
            const SectionTitle('Voice input'),
            Card(
              child: RadioGroup<String>(
                groupValue: settings.whisperModel,
                onChanged: (v) =>
                    settings.setWhisperModel(v ?? settings.whisperModel),
                child: Column(
                  children: [
                    for (final m in const [
                      ('Tiny', 'Fastest · multilingual · 74 MB', 'tiny'),
                      ('Base', 'Recommended · multilingual · 141 MB', 'base'),
                      ('Small', 'More accurate · multilingual · 465 MB', 'small'),
                      ('Medium', 'Accurate · multilingual · 1.43 GB', 'medium'),
                      (
                        'Large',
                        'Best quality · multilingual · 2.88 GB',
                        'large',
                      ),
                    ])
                      RadioTile(
                        icon: Icons.record_voice_over_outlined,
                        label: m.$1,
                        subtitle: m.$2,
                        value: m.$3,
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
            const SectionTitle('Privacy & cloud'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy & network'),
                    subtitle: const Text('Kill switch, per-feature network access, network log'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.privacy),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Cloud providers'),
                    subtitle: const Text('API keys for OpenAI, Anthropic, Gemini, and more'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.providers),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('About'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppConstants.appName} v${AppConstants.versionName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.tagline}\n${settings.processingMode == ProcessingMode.local ? AppConstants.localModePromise : AppConstants.privacyPromise}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      settings.processingMode == ProcessingMode.local
                          ? 'No accounts, ads, or tracking. Your text, recordings, '
                                'and rewrite history stay on this device. AI and '
                                'voice model files are downloaded from Hugging Face '
                                'only when you choose to use them.'
                          : 'No accounts, ads, or tracking. Your text, recordings, '
                                'and rewrite history stay on this device unless you '
                                'choose to send a rewrite to a cloud provider you\'ve '
                                'configured. AI and voice model files are downloaded '
                                'from Hugging Face only when you choose to use them.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const LinkTile(
                      icon: Icons.code_outlined,
                      label: 'Source code on GitHub',
                      url: AppConstants.sourceUrl,
                    ),
                    const LinkTile(
                      icon: Icons.bug_report_outlined,
                      label: 'Report an issue',
                      url: AppConstants.issuesUrl,
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

  /// Persisting the mode and pinning/restoring `RewriteController`'s editor
  /// state are two separate calls on purpose — see
  /// `RewriteController.enterSimpleMode`'s own doc for why hiding the Pro
  /// controls alone isn't enough. This is the other call site for that
  /// same pair, alongside the quick-access toggle in the AppBar.
  void _setUiMode(BuildContext context, UiMode mode) {
    final rewrite = context.read<RewriteController>();
    if (mode == UiMode.simple) {
      rewrite.enterSimpleMode();
    } else {
      rewrite.enterProMode();
    }
    context.read<SettingsController>().setUiMode(mode);
  }
}

/// Radio tile for an enum-valued setting — `RadioTile` (settings_tiles.dart)
/// is typed for `String` values, which most settings on this screen use;
/// this is for the ones that don't.
class _ModeRadioTile<T> extends StatelessWidget {
  const _ModeRadioTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final T value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: Radio<T>(value: value),
      onTap: () => RadioGroup.maybeOf<T>(context)?.onChanged.call(value),
    );
  }
}
