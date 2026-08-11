import 'package:flutter/material.dart';

/// Resolves a stable string token to an [IconData].
///
/// `flutter build apk --release` runs with `--tree-shake-icons`, which keeps
/// only the `IconData` values it can find as **const literals** in the
/// source — it has no way to know what an `IconData` built at runtime from a
/// database row will point to. A tone's icon used to be a compile-time
/// `IconData` constant in a `static const` Dart list; once it comes from
/// SQLite instead, resolving it straight into an `IconData` would render a
/// blank glyph in release while looking perfectly fine in debug, because CI
/// only builds `--debug` (`.github/workflows/ci.yml`) and would never catch it.
///
/// The fix is this fixed, hand-curated map: every value here is a const
/// reference the tree shaker can see, so a token can only ever resolve to an
/// icon that shipped in the binary. Nothing in the app is allowed to
/// construct an `IconData` from a codepoint pulled out of the database.
abstract final class IconCatalog {
  static const Map<String, IconData> _byToken = {
    'business_center_outlined': Icons.business_center_outlined,
    'waving_hand_outlined': Icons.waving_hand_outlined,
    'sentiment_satisfied_alt_outlined': Icons.sentiment_satisfied_alt_outlined,
    'account_balance_outlined': Icons.account_balance_outlined,
    'school_outlined': Icons.school_outlined,
    'palette_outlined': Icons.palette_outlined,
    'compress_outlined': Icons.compress_outlined,
    'trending_up_outlined': Icons.trending_up_outlined,
    'favorite_outline': Icons.favorite_outline,
    'sentiment_very_satisfied_outlined': Icons.sentiment_very_satisfied_outlined,
    'bolt_outlined': Icons.bolt_outlined,
    'handshake_outlined': Icons.handshake_outlined,
    'memory_outlined': Icons.memory_outlined,
    'campaign_outlined': Icons.campaign_outlined,
  };

  /// Shown for a token this catalog doesn't recognise — an id that predates
  /// an icon being removed from the map, or a placeholder tone synthesised
  /// for an id no longer in the store.
  static const IconData fallback = Icons.label_outline;

  static IconData resolve(String? token) =>
      token == null ? fallback : (_byToken[token] ?? fallback);

  /// Every token this catalog can resolve — the data source for a future
  /// icon picker in the tone editor.
  static Iterable<String> get tokens => _byToken.keys;
}
