import 'package:flutter/material.dart';

/// Lets a descendant switch the active bottom-nav tab without a callback
/// threaded through every screen's constructor.
///
/// Replaces `RewriteScreen`'s old `onGoToModels` — a one-off literal that
/// only worked because there was exactly one cross-tab jump anywhere in the
/// app. `home_shell.dart` still indexes tabs with a bare `int` (the
/// `enum AppTab` cleanup is Phase 3 Step 0's job, once Simple/Pro mode
/// needs a mode-dependent tab set); this only removes the constructor prop.
class TabNavigator extends InheritedWidget {
  const TabNavigator({super.key, required this.goToTab, required super.child});

  final void Function(int index) goToTab;

  static TabNavigator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabNavigator>();

  static TabNavigator of(BuildContext context) {
    final navigator = maybeOf(context);
    assert(navigator != null, 'No TabNavigator found above this context.');
    return navigator!;
  }

  @override
  bool updateShouldNotify(TabNavigator oldWidget) => goToTab != oldWidget.goToTab;
}
