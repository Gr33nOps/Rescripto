import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Card(
              color: scheme.errorContainer,
              child: SwitchListTile(
                secondary: Icon(Icons.power_settings_new, color: scheme.onErrorContainer),
                title: Text(
                  'Network kill switch',
                  style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Blocks every network request this app makes, overriding '
                  'every setting below. Model downloads, cloud rewriting, '
                  'everything.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                value: policy.killSwitch,
                onChanged: policy.setKillSwitch,
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('What can reach the network'),
            Card(
              child: Column(
                children: [
                  for (final feature in NetworkFeature.values) ...[
                    _FeatureSwitch(feature: feature, policy: policy),
                    if (feature != NetworkFeature.values.last) const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Network log'),
                subtitle: const Text('Every request this app has made or blocked, host and path only'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.networkLog),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Emergency'),
            Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_outlined, color: scheme.error),
                title: const Text('Panic: wipe & lock down'),
                subtitle: const Text(
                  'Removes every saved API key, disables every cloud '
                  'provider, cancels anything in flight, and turns on the '
                  'kill switch.',
                ),
                onTap: () => _confirmPanic(context),
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
        title: const Text('Wipe & lock down?'),
        content: const Text(
          'This will, right now:\n\n'
          '• Turn on the network kill switch\n'
          '• Cancel any rewrite or transcription in progress\n'
          '• Turn off every configured cloud provider\n'
          '• Permanently delete every saved API key from this device\n\n'
          'You can turn the kill switch back off and re-add keys '
          'afterward. This cannot be undone for the deleted keys.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
              foregroundColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Wipe & lock down'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final report = await context.read<PanicService>().wipeCredentials();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Done. Kill switch on, ${report.providersDisabled} provider(s) '
          'disabled, ${report.requestsCancelled} request(s) cancelled, '
          '${report.credentialsWiped} key(s) deleted.',
        ),
      ),
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
    NetworkFeature.modelDownload: 'The on-device AI model files you choose to download.',
    NetworkFeature.voiceModelDownload: 'The on-device voice model files you choose to download.',
    NetworkFeature.cloudRewrite: 'The text you\'re rewriting, only when you use a cloud provider.',
    NetworkFeature.cloudSpeech: 'Your voice recording, only when you use cloud speech-to-text.',
    NetworkFeature.sync: 'An encrypted backup, when sync is set up. Not available yet.',
    NetworkFeature.updateCheck: 'A check for a new app version. Not available yet.',
  };

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(_titles[feature]!),
      subtitle: Text('Sends: ${_descriptions[feature]}'),
      isThreeLine: true,
      value: policy.isAllowed(feature),
      onChanged: policy.killSwitch
          ? null
          : (value) => policy.setFeatureEnabled(feature, value),
    );
  }
}
