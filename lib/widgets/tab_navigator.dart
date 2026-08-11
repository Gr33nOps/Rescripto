import 'package:flutter/material.dart';

import '../core/app_tab.dart';

/// Lets a descendant switch the active bottom-nav tab without a callback
/// threaded through every screen's constructor.
///
/// Replaces `RewriteScreen`'s old `onGoToModels` — a one-off literal that
/// only worked because there was exactly one cross-tab jump anywhere in the
/// app.
class TabNavigator extends InheritedWidget {
  const TabNavigator({super.key, required this.goToTab, required super.child});

  final void Function(AppTab tab) goToTab;

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
