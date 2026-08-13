import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_tab.dart';
import '../services/share_intent_bridge.dart';
import '../state/history_controller.dart';
import '../state/rewrite_controller.dart';
import '../widgets/tab_navigator.dart';
import 'history_screen.dart';
import 'models_screen.dart';
import 'rewrite_screen.dart';
import 'settings_screen.dart';

/// Bottom-nav shell hosting the main tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _tab = AppTab.rewrite;

  void _goToTab(AppTab tab) {
    setState(() => _tab = tab);
    if (tab == AppTab.history) {
      context.read<HistoryController>().refresh();
    }
  }

  /// Text arrived via PROCESS_TEXT/SEND/the Quick Settings tile lands in
  /// [ShareIntentBridge] as pending state, not a callback — [build] reacts
  /// to it and schedules the actual mutation ([RewriteController.setSource]
  /// plus the tab switch) for after the frame, since neither belongs inside
  /// `build()` itself. Scheduling this more than once before [consume]
  /// clears [ShareIntentBridge.pending] is harmless: every extra callback
  /// before the first one runs is a no-op repeat of the same assignment.
  void _applyPendingIncomingText(BuildContext context, ShareIntentBridge bridge, String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RewriteController>().setSource(text);
      _goToTab(AppTab.rewrite);
      bridge.consume();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bridge = context.watch<ShareIntentBridge>();
    final pending = bridge.pending;
    if (pending != null) {
      _applyPendingIncomingText(context, bridge, pending.text);
    }

    return TabNavigator(
      goToTab: _goToTab,
      child: Scaffold(
        body: IndexedStack(
          index: _tab.index,
          children: const [
            RewriteScreen(),
            HistoryScreen(),
            ModelsScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: (i) => _goToTab(AppTab.values[i]),
          destinations: [
            Semantics(
              identifier: 'nav_rewrite',
              child: const NavigationDestination(
                icon: Icon(Icons.auto_fix_high_outlined),
                selectedIcon: Icon(Icons.auto_fix_high),
                label: 'Rewrite',
              ),
            ),
            Semantics(
              identifier: 'nav_history',
              child: const NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
            ),
            Semantics(
              identifier: 'nav_models',
              child: const NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download_done_outlined),
                label: 'Models',
              ),
            ),
            Semantics(
              identifier: 'nav_settings',
              child: const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
