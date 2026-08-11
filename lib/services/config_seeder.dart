import 'package:sqflite/sqflite.dart';

import '../models/audience_tag.dart';
import '../models/tone_preset.dart';

/// Keeps `tone_preset` and `audience_tag` in step with the built-in seed
/// lists without overwriting anything the user has edited.
///
/// Runs after every database open (`ConfigStore.load`), not inside a
/// migration: a migration is schema-only and gated by the database's own
/// version integer, while built-in *content* — fixing a typo in an
/// instruction, adjusting a temperature — needs its own independent version
/// so a release can ship a content fix without touching the schema at all.
class ConfigSeeder {
  const ConfigSeeder();

  /// Bump when a built-in tone's or audience's own fields change. A row the
  /// user has edited (`user_modified = 1`) is never touched regardless of
  /// this — editing a built-in is meant to detach it from the seed, not to
  /// be silently reverted on the next launch.
  static const int seedVersion = 1;

  Future<void> sync(DatabaseExecutor db) async {
    for (var i = 0; i < ToneLibrary.builtIns.length; i++) {
      await _syncTone(db, ToneLibrary.builtIns[i], sortOrder: i);
    }
    for (var i = 0; i < AudienceLibrary.builtIns.length; i++) {
      await _syncAudience(db, AudienceLibrary.builtIns[i], sortOrder: i);
    }
  }

  Future<void> _syncTone(
    DatabaseExecutor db,
    TonePreset seed, {
    required int sortOrder,
  }) async {
    final existing = await db.query(
      'tone_preset',
      where: 'id = ?',
      whereArgs: [seed.id],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('tone_preset', {
        ...seed.toMap(),
        'is_builtin': 1,
        'is_hidden': 0,
        'sort_order': sortOrder,
        'seed_version': seedVersion,
        'user_modified': 0,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return;
    }

    if (_isCurrent(existing.first)) return;

    await db.update(
      'tone_preset',
      {
        ...seed.toMap(),
        'seed_version': seedVersion,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [seed.id],
    );
  }

  Future<void> _syncAudience(
    DatabaseExecutor db,
    AudienceTag seed, {
    required int sortOrder,
  }) async {
    final existing = await db.query(
      'audience_tag',
      where: 'id = ?',
      whereArgs: [seed.id],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('audience_tag', {
        ...seed.toMap(),
        'is_builtin': 1,
        'is_hidden': 0,
        'sort_order': sortOrder,
        'seed_version': seedVersion,
        'user_modified': 0,
      });
      return;
    }

    if (_isCurrent(existing.first)) return;

    await db.update(
      'audience_tag',
      {...seed.toMap(), 'seed_version': seedVersion},
      where: 'id = ?',
      whereArgs: [seed.id],
    );
  }

  /// True when a row needs no refresh: already edited by the user, or
  /// already carrying this seed's content.
  bool _isCurrent(Map<String, Object?> row) {
    final userModified = (row['user_modified'] as int? ?? 0) != 0;
    final rowSeedVersion = row['seed_version'] as int? ?? 0;
    return userModified || rowSeedVersion >= seedVersion;
  }
}
