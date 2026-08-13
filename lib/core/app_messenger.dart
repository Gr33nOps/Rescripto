import 'package:flutter/material.dart';

/// The single [ScaffoldMessenger] every SnackBar in the app goes through.
///
/// `HomeShell`'s bottom-nav tabs (Rewrite/History/Models/Settings) each have
/// their own local `Scaffold` nested inside `HomeShell`'s own `Scaffold`, and
/// several other screens are pushed as separate routes with their own
/// `Scaffold` again. Calling `ScaffoldMessenger.of(context)` from a screen's
/// `State` (rather than from a widget actually built *underneath* that
/// screen's own `Scaffold`, like `AppBar` content) resolves relative to
/// wherever that `State`'s own context happens to sit in this nested
/// structure — which Scaffold that ends up being is not obvious from the
/// call site, and was the root cause of SnackBars silently failing to show
/// for several call sites (empty-input validation, local-engine errors, a
/// genuine offline network failure, WebDAV password-saved) while others
/// (widgets built inside a screen's own AppBar) worked fine.
///
/// Routing every SnackBar through one explicit, app-wide messenger key
/// removes that ambiguity entirely: it doesn't matter which nested Scaffold
/// a call site's context is closest to, because none of them are asked.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows [content] on the app-wide messenger. Prefer this over
/// `ScaffoldMessenger.of(context).showSnackBar(...)` everywhere — see
/// [scaffoldMessengerKey]'s own doc for why.
void showAppSnackBar(String content) {
  scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(content)));
}
