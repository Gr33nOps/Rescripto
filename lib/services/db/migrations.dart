import 'package:sqflite/sqflite.dart';

/// A single forward schema step.
///
/// Runs inside the transaction sqflite already wraps around `onCreate` and
/// `onUpgrade`, so migrations must not open one of their own — and a throw
/// anywhere in the sequence rolls the whole upgrade back atomically.
typedef Migration = Future<void> Function(Database db);

/// The schema as it shipped through 1.0.3, before this runner existed.
///
/// Frozen. New tables and columns arrive as entries in [kMigrations], never as
/// edits here: a fresh install replays this baseline and then every migration
/// in turn, so editing it would silently diverge new installs from upgraded
/// ones — the exact drift the replay is designed to prevent.
Future<void> createBaseline(Database db) async {
  await db.execute('''
    CREATE TABLE history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      original TEXT NOT NULL,
      rewritten TEXT NOT NULL,
      tone_id TEXT NOT NULL,
      intensity TEXT,
      length TEXT,
      created_at TEXT NOT NULL
    )
  ''');
}

/// Forward migrations, keyed by the schema version each one produces.
///
/// Deliberately empty: the runner ships one release ahead of the first schema
/// change so that when tone presets and the network log arrive there is
/// already a tested upgrade path for the installs in the field. Before this,
/// `openDatabase` was called with no `onUpgrade` at all, so bumping the
/// version would have thrown on open for every existing user.
const Map<int, Migration> kMigrations = <int, Migration>{};
