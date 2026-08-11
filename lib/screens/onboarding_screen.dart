import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../models/processing_mode.dart';
import '../services/network/network_feature.dart';
import '../services/network/network_policy.dart';
import '../state/settings_controller.dart';

enum _Choice { local, cloud, hybrid }

/// First-run flow: pick a processing mode before the app is usable.
///
/// Shown only when [SettingsController.onboardingCompleted] is false —
/// `app.dart` handles the routing, no navigation stack of its own needed.
/// [ProcessingMode.local] is pre-selected; a cloud-capable choice cannot be
/// completed without an affirmative tap on the consent switch below, never
/// a pre-checked box. `onboarding_completed` is written only at the very
/// end, so leaving mid-flow (backgrounding the app, say) means it runs
/// again next launch rather than silently defaulting to whatever was
/// half-chosen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Choice _choice = _Choice.local;
  bool _cloudConsentGiven = false;
  bool _finishing = false;

  bool get _needsCloudConsent => _choice != _Choice.local;
  bool get _canContinue => !_needsCloudConsent || _cloudConsentGiven;

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final settings = context.read<SettingsController>();
    final networkPolicy = context.read<NetworkPolicy>();

    final mode = switch (_choice) {
      _Choice.local => ProcessingMode.local,
      _Choice.cloud => ProcessingMode.cloud,
      _Choice.hybrid => ProcessingMode.hybrid,
    };
    await settings.setProcessingMode(mode);

    if (_needsCloudConsent && _cloudConsentGiven) {
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
    }

    // Last, deliberately — see the class doc.
    await settings.setOnboardingCompleted(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text(
              'Welcome to ${AppConstants.appName}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you\'d like your text handled. You can change this '
              'anytime in Settings.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            RadioGroup<_Choice>(
              groupValue: _choice,
              onChanged: (choice) {
                if (choice == null) return;
                setState(() {
                  _choice = choice;
                  if (choice == _Choice.local) _cloudConsentGiven = false;
                });
              },
              child: Column(
                children: [
                  _ModeCard(
                    value: _Choice.local,
                    icon: Icons.lock_outline,
                    title: 'Private & Offline',
                    description:
                        'Everything happens on this device. No accounts, no '
                        'cloud — nothing you write ever leaves your phone.',
                    recommended: true,
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    value: _Choice.cloud,
                    icon: Icons.cloud_outlined,
                    title: 'Easy Cloud',
                    description:
                        'Rewrite using a cloud AI provider you set up with '
                        'your own API key — no model download, often faster.',
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    value: _Choice.hybrid,
                    icon: Icons.swap_horiz_outlined,
                    title: 'Hybrid',
                    description:
                        'Prefer this device; for very long text, or if '
                        'on-device rewriting fails, Rescripto asks before '
                        'sending anything to the cloud.',
                  ),
                ],
              ),
            ),
            if (_needsCloudConsent) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.tertiaryContainer,
                child: CheckboxListTile(
                  value: _cloudConsentGiven,
                  onChanged: (v) => setState(() => _cloudConsentGiven = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Allow cloud rewriting',
                    style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'The text you rewrite will be sent to whichever cloud '
                    'provider you configure. You can turn this off anytime '
                    'in Privacy settings.',
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_canContinue && !_finishing) ? _finish : null,
              child: _finishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Get started'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.value,
    required this.icon,
    required this.title,
    required this.description,
    this.recommended = false,
  });

  final _Choice value;
  final IconData icon;
  final String title;
  final String description;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = RadioGroup.maybeOf<_Choice>(context)?.groupValue == value;

    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => RadioGroup.maybeOf<_Choice>(context)?.onChanged.call(value),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<_Choice>(value: value),
              const SizedBox(width: 4),
              Icon(icon, color: selected ? scheme.onPrimaryContainer : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? scheme.onPrimaryContainer : null,
                          ),
                        ),
                        if (recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
