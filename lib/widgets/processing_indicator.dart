import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messenger.dart';
import '../services/network/network_policy.dart';
import '../services/routing/target_router.dart';
import '../state/rewrite_controller.dart';

/// AppBar chip showing where the next rewrite would run, and why.
///
/// Reads `RewriteController.routing`, recomputed fresh on every build (it's
/// a plain getter, not cached) from whatever `TargetRouter` currently sees.
/// Rebuilding on `RewriteController`'s own `notifyListeners()` alone isn't
/// enough, though: `routing` also depends on `NetworkPolicy` (the kill
/// switch, per-feature toggles), which is a separate `ChangeNotifier` that
/// `RewriteController` doesn't forward. Without watching it directly here,
/// this chip could keep showing a stale "Not ready"/"Cloud" state after a
/// Privacy-settings change made on another screen, until something
/// unrelated happened to touch `RewriteController`'s own state (typing a
/// character, changing tone, etc.) and trigger a rebuild anyway. Watching
/// both keeps the chip live off either source of change.
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
      backgroundColor: blocked ? scheme.errorContainer : scheme.secondaryContainer,
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
    return decision.reason.startsWith('Hybrid') ? Icons.swap_horiz_outlined : Icons.cloud_outlined;
  }

  String _shortLabel(RoutingDecision decision) {
    if (decision.isBlocked) return 'Not ready';
    final mode = decision.reason.split(' — ').first;
    if (mode != 'Hybrid') return mode;
    final side = decision.target!.providerId == null ? 'On-device' : 'Cloud';
    return 'Hybrid · $side';
  }

  void _showReason(RoutingDecision decision) {
    scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    showAppSnackBar(decision.reason);
  }
}
