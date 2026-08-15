import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messenger.dart';
import '../core/app_routes.dart';
import '../services/network/network_feature.dart';
import '../services/network/network_policy.dart';
import '../services/panic_service.dart';
import '../widgets/settings_tiles.dart';

/// Kill switch, per-feature network access, and the panic button.
///
/// Every switch is wired straight to [NetworkPolicy] — already a
/// `ChangeNotifier` in the tree, so this screen is pure wiring. The one
/// thing that took care: copy names *what leaves the device* per feature
/// ("the text you're rewriting", "your voice recording"), never the generic
/// "allow network" — that distinction is the entire reason there are six
/// separate switches instead of one.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final policy = context.watch<NetworkPolicy>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & network')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
          children: [
            Card(
              color: scheme.errorContainer,
              child: Semantics(
                identifier: 'privacy_kill_switch',
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.power_settings_new,
                    color: scheme.onErrorContainer,
                  ),
                  title: Text(
                    'Network kill switch',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Block all network access from Rescripto.',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                  value: policy.killSwitch,
                  onChanged: policy.setKillSwitch,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('What can reach the network'),
            Card(
              child: Column(
                children: [
                  for (final feature in NetworkFeature.values) ...[
                    _FeatureSwitch(feature: feature, policy: policy),
                    if (feature != NetworkFeature.values.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Semantics(
                identifier: 'privacy_network_log_tile',
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Network log'),
                  subtitle: const Text(
                    'See what left the device and what was blocked',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.networkLog),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Emergency controls'),
            Card(
              child: Semantics(
                identifier: 'privacy_panic_button',
                child: ListTile(
                  leading: Icon(
                    Icons.warning_amber_outlined,
                    color: scheme.error,
                  ),
                  title: const Text('Lock down Rescripto'),
                  subtitle: const Text(
                    'Stop network access and delete saved API keys',
                  ),
                  onTap: () => _confirmPanic(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPanic(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lock down Rescripto?'),
        content: const Text(
          'Rescripto will immediately:\n\n'
          '• Block all network access\n'
          '• Cancel active rewrites and transcriptions\n'
          '• Disable every cloud provider\n'
          '• Permanently delete saved API keys\n\n'
          'You can reconnect providers later, but deleted keys cannot be '
          'recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          Semantics(
            identifier: 'privacy_panic_confirm',
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(
                  dialogContext,
                ).colorScheme.errorContainer,
                foregroundColor: Theme.of(
                  dialogContext,
                ).colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Lock down'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<PanicService>().wipeCredentials();
    if (!context.mounted) return;

    showAppSnackBar(
      'Rescripto is locked down. Network access is off and saved API keys were deleted.',
    );
  }
}

class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({required this.feature, required this.policy});

  final NetworkFeature feature;
  final NetworkPolicy policy;

  static const _titles = {
    NetworkFeature.modelDownload: 'AI model downloads',
    NetworkFeature.voiceModelDownload: 'Voice model downloads',
    NetworkFeature.cloudRewrite: 'Cloud rewriting',
    NetworkFeature.cloudSpeech: 'Cloud speech-to-text',
    NetworkFeature.sync: 'Backup sync',
    NetworkFeature.updateCheck: 'Update checks',
  };

  // What leaves the device — never "allow network access".
  static const _descriptions = {
    NetworkFeature.modelDownload:
        'The on-device AI model files you choose to download.',
    NetworkFeature.voiceModelDownload:
        'The on-device voice model files you choose to download.',
    NetworkFeature.cloudRewrite:
        'The text you\'re rewriting, only when you use a cloud provider.',
    NetworkFeature.cloudSpeech:
        'Your voice recording, only when you use cloud speech-to-text.',
    NetworkFeature.sync:
        'An encrypted backup file, only when you sync to a WebDAV server you '
        'set up. The server never sees your text unencrypted.',
    NetworkFeature.updateCheck:
        'A check for a new app version. Not available yet.',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'privacy_feature_switch_${feature.name}',
      child: SwitchListTile(
        title: Text(_titles[feature]!),
        subtitle: Text(_descriptions[feature]!),
        value: policy.isAllowed(feature),
        onChanged: policy.killSwitch
            ? null
            : (value) => policy.setFeatureEnabled(feature, value),
      ),
    );
  }
}
