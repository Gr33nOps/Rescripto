/// The app's bottom-nav tabs, in display order.
///
/// Replaces the bare `int _index` `home_shell.dart` used to carry directly,
/// and the literal `2`/`1` that leaked out of it into `TabNavigator.goToTab`
/// call sites — those broke silently the moment anything needed to reason
/// about *which* tab a number meant. `IndexedStack`/`NavigationBar` still
/// need a plain `int` at the leaf (`AppTab.index`), but nothing above that
/// leaf should ever see one.
enum AppTab { rewrite, history, models, settings }
