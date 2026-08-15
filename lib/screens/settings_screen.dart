import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_routes.dart';
import '../core/constants.dart';
import '../models/processing_mode.dart';
import '../models/ui_mode.dart';
import '../services/providers/provider_registry.dart';
import '../speech/speech_engine_resolver.dart';
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
                child: Column(
                  children: [
                    Semantics(
                      identifier: 'theme_radio_system',
                      child: const RadioTile(
                        icon: Icons.brightness_auto_outlined,
                        label: 'Follow system',
                        value: 'system',
                      ),
                    ),
                    Semantics(
                      identifier: 'theme_radio_light',
                      child: const RadioTile(
                        icon: Icons.light_mode_outlined,
                        label: 'Light',
                        value: 'light',
                      ),
                    ),
                    Semantics(
                      identifier: 'theme_radio_dark',
                      child: const RadioTile(
                        icon: Icons.dark_mode_outlined,
                        label: 'Dark',
                        value: 'dark',
                      ),
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
                onChanged: (mode) =>
                    settings.setProcessingMode(mode ?? settings.processingMode),
                child: Column(
                  children: [
                    Semantics(
                      identifier: 'processing_mode_local',
                      child: _ModeRadioTile(
                        icon: Icons.lock_outline,
                        label: 'Local',
                        subtitle: 'Rewrites stay on this device.',
                        value: ProcessingMode.local,
                      ),
                    ),
                    Semantics(
                      identifier: 'processing_mode_cloud',
                      child: _ModeRadioTile(
                        icon: Icons.cloud_outlined,
                        label: 'Cloud',
                        subtitle: 'Sends rewrites to the provider you choose.',
                        value: ProcessingMode.cloud,
                      ),
                    ),
                    Semantics(
                      identifier: 'processing_mode_hybrid',
                      child: _ModeRadioTile(
                        icon: Icons.swap_horiz_outlined,
                        label: 'Hybrid',
                        subtitle:
                            'Uses this device for shorter text and cloud for longer text.',
                        value: ProcessingMode.hybrid,
                      ),
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
                onChanged: (mode) =>
                    _setUiMode(context, mode ?? settings.uiMode),
                child: Column(
                  children: [
                    Semantics(
                      identifier: 'ui_mode_radio_simple',
                      child: _ModeRadioTile(
                        icon: Icons.tune_outlined,
                        label: 'Simple',
                        subtitle: 'Tone and rewrite only.',
                        value: UiMode.simple,
                      ),
                    ),
                    Semantics(
                      identifier: 'ui_mode_radio_pro',
                      child: _ModeRadioTile(
                        icon: Icons.tune,
                        label: 'Pro',
                        subtitle:
                            'Intensity, length, audience, instructions, and variants.',
                        value: UiMode.pro,
                      ),
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
                  Semantics(
                    identifier: 'settings_tones_tile',
                    child: ListTile(
                      leading: const Icon(Icons.style_outlined),
                      title: const Text('Tones'),
                      subtitle: const Text(
                        'Edit, reorder, add, or remove tone presets',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed(AppRoutes.tones),
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    identifier: 'settings_audiences_tile',
                    child: ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('Audiences'),
                      subtitle: const Text(
                        'Edit, reorder, add, or remove audience tags',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed(AppRoutes.audiences),
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    identifier: 'settings_workflows_tile',
                    child: ListTile(
                      leading: const Icon(Icons.route_outlined),
                      title: const Text('Workflows'),
                      subtitle: const Text(
                        'Chain multiple rewrite steps together',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed(AppRoutes.workflows),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Advanced'),
            Card(
              child: Semantics(
                identifier: 'settings_advanced_tile',
                child: ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Performance'),
                  subtitle: const Text('Tune model speed and memory use'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.advanced),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Voice input'),
            const _SpeechEngineCard(),
            if (settings.speechEngine != SpeechEngineResolver.cloudId) ...[
              const SizedBox(height: 12),
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
                        (
                          'Small',
                          'More accurate · multilingual · 465 MB',
                          'small',
                        ),
                        (
                          'Medium',
                          'Accurate · multilingual · 1.43 GB',
                          'medium',
                        ),
                        (
                          'Large',
                          'Best quality · multilingual · 2.88 GB',
                          'large',
                        ),
                      ])
                        Semantics(
                          identifier: 'whisper_model_radio_${m.$3}',
                          child: RadioTile(
                            icon: Icons.record_voice_over_outlined,
                            label: m.$1,
                            subtitle: m.$2,
                            value: m.$3,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'The selected voice model downloads the first time you '
                          'dictate.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const SectionTitle('Privacy & cloud'),
            Card(
              child: Column(
                children: [
                  Semantics(
                    identifier: 'settings_privacy_tile',
                    child: ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy & network'),
                      subtitle: const Text(
                        'Control and review network activity',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed(AppRoutes.privacy),
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    identifier: 'settings_providers_tile',
                    child: ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: const Text('Cloud providers'),
                      subtitle: const Text(
                        'Connect a provider with your own API key',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed(AppRoutes.providers),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Backup'),
            Card(
              child: Semantics(
                identifier: 'settings_backup_tile',
                child: ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup'),
                  subtitle: const Text(
                    'Export, restore, or sync an encrypted copy',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.backup),
                ),
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
                          ? 'No account. No ads or tracking.\n\nLocal rewrites, '
                                'on-device dictation, and history stay on this device.'
                          : 'No account. No ads or tracking.\n\nCloud requests go '
                                'only to providers you configure and choose to use.',
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

/// Where voice input is transcribed.
///
/// Only two options. Android's own `SpeechRecognizer` has a `SpeechEngine`
/// implementation, but every method on it throws — it needs a platform
/// channel that isn't built — so it is deliberately not offered here rather
/// than shipped as a choice that always fails. Cloud is disabled unless a
/// transcription-capable provider is actually enabled, so the option is
/// never selectable and then refused at record time.
class _SpeechEngineCard extends StatelessWidget {
  const _SpeechEngineCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    // Watched so enabling a provider elsewhere re-enables the Cloud option
    // without needing this screen rebuilt by hand.
    context.watch<ProviderRegistry>();
    final resolver = context.read<SpeechEngineResolver>();
    final cloudAvailable = resolver.hasCloudSpeechProvider;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          RadioGroup<String>(
            groupValue: settings.speechEngine,
            onChanged: (v) =>
                settings.setSpeechEngine(v ?? SpeechEngineResolver.localId),
            child: Column(
              children: [
                Semantics(
                  identifier: 'speech_engine_local',
                  child: const RadioListTile<String>(
                    value: SpeechEngineResolver.localId,
                    secondary: Icon(Icons.phone_android_outlined),
                    title: Text('On-device'),
                    subtitle: Text('Private. Downloads a voice model once.'),
                  ),
                ),
                Semantics(
                  identifier: 'speech_engine_cloud',
                  child: RadioListTile<String>(
                    value: SpeechEngineResolver.cloudId,
                    enabled: cloudAvailable,
                    secondary: const Icon(Icons.cloud_outlined),
                    title: const Text('Cloud'),
                    subtitle: Text(
                      cloudAvailable
                          ? 'Faster on older phones. Your recording is uploaded '
                                'to your configured provider.'
                          : 'Needs a provider that supports transcription '
                                '(OpenAI or Groq) enabled in Cloud providers.',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (settings.speechEngine == SpeechEngineResolver.cloudId)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Cloud transcription sends the whole recording to your '
                'provider. It appears in the Network log like any other '
                'request.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
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
