import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/audience_tag.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/services/config_seeder.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_seeder');
    db = await AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    ).db;
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  group('ConfigSeeder.sync', () {
    test('inserts every built-in tone and audience on a fresh database', () async {
      await const ConfigSeeder().sync(db);

      final tones = await db.query('tone_preset');
      final audiences = await db.query('audience_tag');
      expect(tones, hasLength(ToneLibrary.builtIns.length));
      expect(audiences, hasLength(AudienceLibrary.builtIns.length));
    });

    test('preserves declaration order via sort_order', () async {
      await const ConfigSeeder().sync(db);

      final rows = await db.query('tone_preset', orderBy: 'sort_order');
      expect(
        rows.map((r) => r['id']).toList(),
        ToneLibrary.builtIns.map((t) => t.id).toList(),
      );
    });

    test('marks seeded rows as built-in and not user-modified', () async {
      await const ConfigSeeder().sync(db);

      final row = (await db.query(
        'tone_preset',
        where: 'id = ?',
        whereArgs: ['professional'],
      )).single;
      expect(row['is_builtin'], 1);
      expect(row['is_hidden'], 0);
      expect(row['user_modified'], 0);
      expect(row['seed_version'], ConfigSeeder.seedVersion);
    });

    test('running sync twice does not duplicate rows', () async {
      await const ConfigSeeder().sync(db);
      await const ConfigSeeder().sync(db);

      final tones = await db.query('tone_preset');
      expect(tones, hasLength(ToneLibrary.builtIns.length));
    });

    test('never touches a row the user has modified', () async {
      await const ConfigSeeder().sync(db);
      await db.update(
        'tone_preset',
        {
          'name': 'My Professional',
          'instruction': 'something the user wrote',
          'user_modified': 1,
        },
        where: 'id = ?',
        whereArgs: ['professional'],
      );

      await const ConfigSeeder().sync(db);

      final row = (await db.query(
        'tone_preset',
        where: 'id = ?',
        whereArgs: ['professional'],
      )).single;
      expect(row['name'], 'My Professional');
      expect(row['instruction'], 'something the user wrote');
    });

    test('refreshes an un-modified row whose seed_version is stale', () async {
      await const ConfigSeeder().sync(db);
      // Simulate the previous release's seed: older content, older version.
      await db.update(
        'tone_preset',
        {'name': 'Old Name', 'seed_version': 0},
        where: 'id = ?',
        whereArgs: ['professional'],
      );

      await const ConfigSeeder().sync(db);

      final row = (await db.query(
        'tone_preset',
        where: 'id = ?',
        whereArgs: ['professional'],
      )).single;
      expect(row['name'], 'Professional');
      expect(row['seed_version'], ConfigSeeder.seedVersion);
    });
  });
}
