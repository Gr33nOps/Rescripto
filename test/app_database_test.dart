import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/db/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stand-ins for real schema changes, so the runner is exercised without
/// dragging the production database through throwaway versions.
final Map<int, Migration> _testMigrations = <int, Migration>{
  2: (db) async {
    await db.execute(
      'CREATE TABLE note (id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
  },
  3: (db) async {
    await db.execute(
      'CREATE INDEX idx_history_created_at ON history(created_at DESC)',
    );
    await db.execute(
      'ALTER TABLE note ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
    );
  },
};

/// Every object in the schema, in a stable order.
Future<List<String>> _schemaOf(Database db) async {
  final rows = await db.rawQuery(
    "SELECT type, name, sql FROM sqlite_master "
    "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
  );
  return rows
      .map((r) => '${r['type']}|${r['name']}|${(r['sql'] as String?) ?? ''}')
      .toList();
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => tempDir = Directory.systemTemp.createTempSync('rescripto_db'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  String pathFor(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  group('AppDatabase migration runner', () {
    test('an upgraded database ends up with the same schema as a fresh one', () async {
      // The bug this guards against: a new table added only to the baseline
      // (or only to a migration) leaves installs that upgraded and installs
      // that started fresh on quietly different schemas.
      final upgradedPath = pathFor('upgraded.db');
      final v1 = await AppDatabase(version: 1, migrations: const {})
          .openAt(upgradedPath);
      await v1.close();
      final upgraded = await AppDatabase(
        version: 3,
        migrations: _testMigrations,
      ).openAt(upgradedPath);

      final fresh = await AppDatabase(
        version: 3,
        migrations: _testMigrations,
      ).openAt(pathFor('fresh.db'));

      expect(await _schemaOf(upgraded), await _schemaOf(fresh));
      expect(await upgraded.getVersion(), 3);

      await upgraded.close();
      await fresh.close();
    });

    test('history survives an upgrade', () async {
      final path = pathFor('data.db');
      final v1 = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);
      await v1.insert('history', {
        'original': 'hello',
        'rewritten': 'Hello.',
        'tone_id': 'professional',
        'created_at': DateTime.utc(2026).toIso8601String(),
      });
      await v1.close();

      final upgraded = await AppDatabase(
        version: 3,
        migrations: _testMigrations,
      ).openAt(path);
      final rows = await upgraded.query('history');

      expect(rows, hasLength(1));
      expect(rows.single['rewritten'], 'Hello.');
      await upgraded.close();
    });

    test('a gap in the migration map fails loudly instead of silently', () async {
      final path = pathFor('gap.db');
      final v1 = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);
      await v1.close();

      // Version bumped to 3 but only step 2 registered.
      await expectLater(
        AppDatabase(version: 3, migrations: {2: _testMigrations[2]!})
            .openAt(path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('version 3'),
          ),
        ),
      );
    });

    test('opening with an older build preserves the newer file', () async {
      // A sideloaded older APK must not be able to destroy the user's only
      // copy of their history, which is what onDatabaseDowngradeDelete does.
      final path = pathFor('downgrade.db');
      final newer = await AppDatabase(
        version: 3,
        migrations: _testMigrations,
      ).openAt(path);
      await newer.insert('note', {'body': 'written by a newer build'});
      await newer.close();

      final older = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);

      expect(
        File('$path.v3.bak').existsSync(),
        isTrue,
        reason: 'the newer database should be moved aside, not deleted',
      );
      expect(await older.getVersion(), 1);
      // The old build gets a usable, empty database rather than an error.
      expect(await older.query('history'), isEmpty);
      await older.close();
    });

    test('a same-version open leaves the file alone', () async {
      final path = pathFor('same.db');
      final first = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);
      await first.insert('history', {
        'original': 'a',
        'rewritten': 'b',
        'tone_id': 'casual',
        'created_at': DateTime.utc(2026).toIso8601String(),
      });
      await first.close();

      final second = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);

      expect(File('$path.v1.bak').existsSync(), isFalse);
      expect(await second.query('history'), hasLength(1));
      await second.close();
    });
  });

  group('AppDatabase baseline', () {
    test('creates the 1.0.3 history table', () async {
      final db = await AppDatabase(version: 1, migrations: const {})
          .openAt(pathFor('baseline.db'));
      final columns = await db.rawQuery('PRAGMA table_info(history)');

      expect(
        columns.map((c) => c['name']).toSet(),
        {'id', 'original', 'rewritten', 'tone_id', 'intensity', 'length', 'created_at'},
      );
      await db.close();
    });
  });

  group('real kMigrations (default AppDatabase())', () {
    test('a fresh database has tone_preset, audience_tag, and network_log', () async {
      final db = await AppDatabase().openAt(pathFor('real_fresh.db'));
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((t) => t['name']),
        containsAll(['history', 'tone_preset', 'audience_tag', 'network_log']),
      );
      await db.close();
    });

    test('upgrading a real v2 database adds network_log without touching config', () async {
      final path = pathFor('real_v2_upgrade.db');
      final v2 = await AppDatabase(version: 2, migrations: {2: kMigrations[2]!})
          .openAt(path);
      await v2.insert('tone_preset', {
        'id': 'professional',
        'name': 'Professional',
        'icon_token': 'business_center_outlined',
        'instruction': 'Be professional.',
        'temperature': 0.4,
        'updated_at': DateTime.utc(2026).toIso8601String(),
      });
      await v2.close();

      final upgraded = await AppDatabase().openAt(path);
      expect(await upgraded.query('tone_preset'), hasLength(1));
      expect(await upgraded.query('network_log'), isEmpty);
      await upgraded.close();
    });

    test('the history(created_at) index exists', () async {
      final db = await AppDatabase().openAt(pathFor('real_index.db'));
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'history'",
      );
      expect(indexes.map((i) => i['name']), contains('idx_history_created_at'));
      await db.close();
    });

    test('upgrading a real 1.0.3 database adds the config tables without touching history', () async {
      final path = pathFor('real_upgrade.db');
      final v1 = await AppDatabase(version: 1, migrations: const {})
          .openAt(path);
      await v1.insert('history', {
        'original': 'a',
        'rewritten': 'b',
        'tone_id': 'professional',
        'created_at': DateTime.utc(2026).toIso8601String(),
      });
      await v1.close();

      final upgraded = await AppDatabase().openAt(path);

      expect(await upgraded.query('history'), hasLength(1));
      expect(await upgraded.query('tone_preset'), isEmpty);
      await upgraded.close();
    });
  });
}
