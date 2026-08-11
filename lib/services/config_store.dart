import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/audience_tag.dart';
import '../models/tone_preset.dart';
import 'config_seeder.dart';
import 'db/app_database.dart';

/// User-editable tones and audiences, backed by SQLite.
///
/// `ToneLibrary.builtIns` and `AudienceLibrary.builtIns` stay as read-only
/// seed data — see `ConfigSeeder` — and this is what the rest of the app
/// actually reads from: an in-memory cache kept in sync with the database, so
/// `ToneSelector` isn't hitting SQLite on every frame.
class ConfigStore extends ChangeNotifier {
  ConfigStore(this._database, {this._seeder = const ConfigSeeder()});

  final AppDatabase _database;
  final ConfigSeeder _seeder;

  List<TonePreset> _tones = const [];
  List<AudienceTag> _audiences = const [];
  bool _isLoaded = false;

  List<TonePreset> get tones => List.unmodifiable(_tones);
  List<AudienceTag> get audiences => List.unmodifiable(_audiences);

  /// True once [load] has run. Awaited before `runApp` (see `main.dart`), so
  /// nothing in the widget tree should ever observe this false.
  bool get isLoaded => _isLoaded;

  /// Looks up a tone by id, synthesising a placeholder for one no longer in
  /// the store rather than silently substituting an unrelated tone.
  ///
  /// The API this replaces (`ToneLibrary.byId`) fell back to the first tone
  /// in the list for any unknown id, so a deleted or corrupted tone id
  /// rendered old history entries as "Professional" with no sign anything
  /// was wrong. That was harmless while tones were a fixed, undeletable list;
  /// it stops being a theoretical edge case now that they can be removed.
  TonePreset toneById(String id) {
    for (final tone in _tones) {
      if (tone.id == id) return tone;
    }
    return TonePreset(
      id: id,
      name: id,
      iconToken: '',
      description: '',
      instruction: '',
      temperature: 0.5,
    );
  }

  Future<void> load() async {
    final db = await _database.db;
    await _seeder.sync(db);
    await _reload();
    _isLoaded = true;
  }

  /// Creates a tone, or overwrites one with a matching id and marks it
  /// user-modified so [ConfigSeeder] stops refreshing it from the built-in.
  Future<void> upsertTone(TonePreset tone) async {
    final db = await _database.db;
    final existing = await _row(db, 'tone_preset', tone.id);
    final now = DateTime.now().toIso8601String();

    if (existing == null) {
      final nextOrder = await _nextSortOrder(db, 'tone_preset');
      await db.insert('tone_preset', {
        ...tone.toMap(),
        'is_builtin': 0,
        'is_hidden': 0,
        'sort_order': nextOrder,
        'seed_version': 0,
        'user_modified': 1,
        'updated_at': now,
      });
    } else {
      await db.update(
        'tone_preset',
        {...tone.toMap(), 'user_modified': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [tone.id],
      );
    }
    await _reload();
  }

  /// Removes a tone. A built-in is hidden (soft-deleted, reversible via
  /// [resetToneToDefault]); a user-created tone has no built-in to fall back
  /// to, so it's deleted outright.
  Future<void> hideTone(String id) async {
    final db = await _database.db;
    final row = await _row(db, 'tone_preset', id);
    if (row == null) return;

    if (_isBuiltin(row)) {
      await db.update(
        'tone_preset',
        {'is_hidden': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete('tone_preset', where: 'id = ?', whereArgs: [id]);
    }
    await _reload();
  }

  /// Discards any edits to a built-in tone and un-hides it. No-op for a
  /// user-created tone, which has no built-in to reset to.
  Future<void> resetToneToDefault(String id) async {
    final seed = _findBuiltinTone(id);
    if (seed == null) return;

    final db = await _database.db;
    await db.update(
      'tone_preset',
      {
        ...seed.toMap(),
        'is_hidden': 0,
        'user_modified': 0,
        'seed_version': ConfigSeeder.seedVersion,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reload();
  }

  /// Persists a new display order. Takes every visible tone's id, in the
  /// order they should appear.
  Future<void> reorderTones(List<String> idsInOrder) async {
    final db = await _database.db;
    final batch = db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update(
        'tone_preset',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [idsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
    await _reload();
  }

  Future<void> upsertAudience(AudienceTag audience) async {
    final db = await _database.db;
    final existing = await _row(db, 'audience_tag', audience.id);

    if (existing == null) {
      final nextOrder = await _nextSortOrder(db, 'audience_tag');
      await db.insert('audience_tag', {
        ...audience.toMap(),
        'is_builtin': 0,
        'is_hidden': 0,
        'sort_order': nextOrder,
        'seed_version': 0,
        'user_modified': 1,
      });
    } else {
      await db.update(
        'audience_tag',
        {...audience.toMap(), 'user_modified': 1},
        where: 'id = ?',
        whereArgs: [audience.id],
      );
    }
    await _reload();
  }

  Future<void> hideAudience(String id) async {
    final db = await _database.db;
    final row = await _row(db, 'audience_tag', id);
    if (row == null) return;

    if (_isBuiltin(row)) {
      await db.update(
        'audience_tag',
        {'is_hidden': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete('audience_tag', where: 'id = ?', whereArgs: [id]);
    }
    await _reload();
  }

  Future<void> _reload() async {
    final db = await _database.db;
    final toneRows = await db.query(
      'tone_preset',
      where: 'is_hidden = 0',
      orderBy: 'sort_order',
    );
    final audienceRows = await db.query(
      'audience_tag',
      where: 'is_hidden = 0',
      orderBy: 'sort_order',
    );
    _tones = toneRows.map(TonePreset.fromMap).toList();
    _audiences = audienceRows.map(AudienceTag.fromMap).toList();
    notifyListeners();
  }

  Future<Map<String, Object?>?> _row(
    DatabaseExecutor db,
    String table,
    String id,
  ) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  bool _isBuiltin(Map<String, Object?> row) =>
      (row['is_builtin'] as int? ?? 0) != 0;

  Future<int> _nextSortOrder(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('SELECT MAX(sort_order) AS m FROM $table');
    final max = rows.first['m'] as int?;
    return (max ?? -1) + 1;
  }

  TonePreset? _findBuiltinTone(String id) {
    for (final tone in ToneLibrary.builtIns) {
      if (tone.id == id) return tone;
    }
    return null;
  }
}
