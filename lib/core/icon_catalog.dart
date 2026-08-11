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
    // One per built-in tone (ToneLibrary.builtIns).
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
    // The rest: a wider picker for a user-created tone, added for the tone
    // editor (`lib/screens/authoring/tone_editor_screen.dart`) — this
    // class's own doc named it as the reason `tokens` exists at all.
    'auto_awesome_outlined': Icons.auto_awesome_outlined,
    'chat_bubble_outline': Icons.chat_bubble_outline,
    'lightbulb_outline': Icons.lightbulb_outline,
    'mood_outlined': Icons.mood_outlined,
    'mood_bad_outlined': Icons.mood_bad_outlined,
    'psychology_outlined': Icons.psychology_outlined,
    'gavel_outlined': Icons.gavel_outlined,
    'menu_book_outlined': Icons.menu_book_outlined,
    'theater_comedy_outlined': Icons.theater_comedy_outlined,
    'nightlight_outlined': Icons.nightlight_outlined,
    'wb_sunny_outlined': Icons.wb_sunny_outlined,
    'eco_outlined': Icons.eco_outlined,
    'rocket_launch_outlined': Icons.rocket_launch_outlined,
    'star_outline': Icons.star_outline,
    'flag_outlined': Icons.flag_outlined,
    'groups_outlined': Icons.groups_outlined,
    'record_voice_over_outlined': Icons.record_voice_over_outlined,
    'article_outlined': Icons.article_outlined,
    'edit_note_outlined': Icons.edit_note_outlined,
    'psychology_alt_outlined': Icons.psychology_alt_outlined,
    'diversity_3_outlined': Icons.diversity_3_outlined,
    'spa_outlined': Icons.spa_outlined,
    'local_fire_department_outlined': Icons.local_fire_department_outlined,
    'shield_outlined': Icons.shield_outlined,
    'public_outlined': Icons.public_outlined,
    'terminal_outlined': Icons.terminal_outlined,
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
