import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messenger.dart';
import '../services/network/network_policy.dart';
import '../services/providers/provider_registry.dart';
import '../services/routing/target_router.dart';
import '../state/models_controller.dart';
import '../state/rewrite_controller.dart';
import '../state/settings_controller.dart';

/// AppBar chip showing where the next rewrite would run, and why.
///
/// Reads `RewriteController.routing`, recomputed fresh on every build (it's
/// a plain getter, not cached) from whatever `TargetRouter` currently sees.
/// Routing also depends on independent settings, model, provider and network
/// notifiers. Watch each one here: the chip is a const child of RewriteScreen,
/// so rebuilding that parent alone does not refresh a stale routing label.
///
/// In Hybrid mode the label always names the actual side ("Hybrid ·
/// On-device" / "Hybrid · Cloud"), never a bare "Hybrid" — a badge that
/// doesn't say which way it's leaning is exactly the failure mode this
/// exists to avoid. Tapping shows the full one-sentence reason, since a
/// tooltip alone isn't discoverable with touch.
class ProcessingIndicator extends StatelessWidget {
  const ProcessingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController>();
    context.watch<ModelsController>();
    context.watch<ProviderRegistry>();
    context.watch<NetworkPolicy>();
    final decision = context.watch<RewriteController>().routing;
    final scheme = Theme.of(context).colorScheme;
    final blocked = decision.isBlocked;

    return ActionChip(
      avatar: Icon(_iconFor(decision), size: 16),
      label: Text(_shortLabel(decision)),
      labelStyle: TextStyle(
        fontSize: 12,
        color: blocked ? scheme.onErrorContainer : scheme.onSecondaryContainer,
      ),
      backgroundColor: blocked
          ? scheme.errorContainer
          : scheme.secondaryContainer,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () => _showReason(decision),
    );
  }

  IconData _iconFor(RoutingDecision decision) {
    if (decision.isBlocked) return Icons.error_outline;
    final target = decision.target!;
    if (target.providerId == null) return Icons.lock_outline;
    return decision.reason.startsWith('Hybrid')
        ? Icons.swap_horiz_outlined
        : Icons.cloud_outlined;
  }

  String _shortLabel(RoutingDecision decision) {
    if (decision.isBlocked) return 'Setup needed';
    final mode = decision.reason.split(': ').first;
    if (mode != 'Hybrid') return mode;
    final side = decision.target!.providerId == null ? 'On-device' : 'Cloud';
    return 'Hybrid · $side';
  }

  void _showReason(RoutingDecision decision) {
    scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    showAppSnackBar(decision.reason);
  }
}
