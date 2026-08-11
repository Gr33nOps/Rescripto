import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_tab.dart';
import '../state/history_controller.dart';
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

  @override
  Widget build(BuildContext context) {
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.auto_fix_high_outlined),
              selectedIcon: Icon(Icons.auto_fix_high),
              label: 'Rewrite',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_done_outlined),
              label: 'Models',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
