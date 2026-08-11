import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/audience_tag.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late ConfigStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_config_store');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    store = ConfigStore(database);
    await store.load();
  });

  tearDown(() async {
    // Windows keeps the file locked until the connection is closed;
    // deleting the directory first fails with a sharing violation.
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('ConfigStore.load', () {
    test('populates tones and audiences from the built-in seed', () {
      expect(store.tones, hasLength(ToneLibrary.builtIns.length));
      expect(store.audiences, hasLength(AudienceLibrary.builtIns.length));
      expect(store.isLoaded, isTrue);
    });

    test('tones keep their seed order', () {
      expect(
        store.tones.map((t) => t.id).toList(),
        ToneLibrary.builtIns.map((t) => t.id).toList(),
      );
    });

    test('seeded tones are flagged isBuiltin so an editor can offer "Reset to default"', () {
      expect(store.tones.every((t) => t.isBuiltin), isTrue);
    });

    test('a user-created tone is not flagged isBuiltin', () async {
      await store.upsertTone(const TonePreset(
        id: 'user_builtin_check',
        name: 'Mine',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: '',
        temperature: 0.5,
      ));
      expect(store.toneById('user_builtin_check').isBuiltin, isFalse);
    });
  });

  group('ConfigStore.toneById', () {
    test('returns the matching tone', () {
      expect(store.toneById('casual').name, 'Casual');
    });

    test('synthesises a named placeholder for an unknown id, not the first tone', () {
      // The bug this replaces: ToneLibrary.byId fell back to the first tone
      // in the list, so a deleted tone's old history entries would silently
      // relabel themselves "Professional" with no sign anything was wrong.
      final placeholder = store.toneById('a-deleted-tone-id');
      expect(placeholder.id, 'a-deleted-tone-id');
      expect(placeholder.name, 'a-deleted-tone-id');
      expect(placeholder.name, isNot('Professional'));
    });
  });

  group('ConfigStore.upsertTone', () {
    test('creates a new tone that appears in tones', () async {
      await store.upsertTone(const TonePreset(
        id: 'user_1',
        name: 'My Tone',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: 'Be terse.',
        temperature: 0.5,
      ));

      expect(store.tones.map((t) => t.id), contains('user_1'));
      expect(store.toneById('user_1').name, 'My Tone');
    });

    test('editing a built-in marks it user-modified so the seeder leaves it alone', () async {
      final edited = store.toneById('professional').copyWith(name: 'Work Voice');
      await store.upsertTone(edited);

      expect(store.toneById('professional').name, 'Work Voice');

      // A second load (fresh store, same database file) re-runs the seeder;
      // the edit must survive it.
      final resyncedDb = AppDatabase(
        path: '${tempDir.path}${Platform.pathSeparator}test.db',
      );
      final resynced = ConfigStore(resyncedDb);
      await resynced.load();
      expect(resynced.toneById('professional').name, 'Work Voice');
      await resyncedDb.close();
    });
  });

  group('ConfigStore.hideTone', () {
    test('hides a built-in rather than deleting it', () async {
      await store.hideTone('professional');
      expect(store.tones.map((t) => t.id), isNot(contains('professional')));
    });

    test('deletes a user-created tone outright', () async {
      await store.upsertTone(const TonePreset(
        id: 'user_2',
        name: 'Temp',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: '',
        temperature: 0.5,
      ));

      await store.hideTone('user_2');

      expect(store.tones.map((t) => t.id), isNot(contains('user_2')));
      // Confirm it's gone, not merely hidden, by resetting — a reset on an
      // id with no built-in and no row should be a silent no-op either way,
      // but toneById should synthesise a placeholder, not find a hidden row.
      expect(store.toneById('user_2').name, 'user_2');
    });
  });

  group('ConfigStore.hiddenTones', () {
    test('lists a hidden built-in so it can be brought back', () async {
      await store.hideTone('professional');
      final hidden = await store.hiddenTones();
      expect(hidden.map((t) => t.id), contains('professional'));
    });

    test('never lists a deleted custom tone — it has no default to reset to', () async {
      await store.upsertTone(const TonePreset(
        id: 'user_hidden_check',
        name: 'Temp',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: '',
        temperature: 0.5,
      ));
      await store.hideTone('user_hidden_check');

      final hidden = await store.hiddenTones();
      expect(hidden.map((t) => t.id), isNot(contains('user_hidden_check')));
    });

    test('is empty when nothing is hidden', () async {
      expect(await store.hiddenTones(), isEmpty);
    });
  });

  group('ConfigStore.resetToneToDefault', () {
    test('restores an edited built-in to its seed content', () async {
      await store.upsertTone(
        store.toneById('professional').copyWith(name: 'Something Else'),
      );
      expect(store.toneById('professional').name, 'Something Else');

      await store.resetToneToDefault('professional');

      expect(store.toneById('professional').name, 'Professional');
    });

    test('un-hides a hidden built-in', () async {
      await store.hideTone('professional');
      expect(store.tones.map((t) => t.id), isNot(contains('professional')));

      await store.resetToneToDefault('professional');

      expect(store.tones.map((t) => t.id), contains('professional'));
    });

    test('is a no-op for a tone with no built-in to reset to', () async {
      await store.upsertTone(const TonePreset(
        id: 'user_3',
        name: 'Custom',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: '',
        temperature: 0.5,
      ));

      await store.resetToneToDefault('user_3');

      expect(store.toneById('user_3').name, 'Custom');
    });
  });

  group('ConfigStore.reorderTones', () {
    test('changes the order tones are returned in', () async {
      final ids = store.tones.map((t) => t.id).toList();
      final reversed = ids.reversed.toList();

      await store.reorderTones(reversed);

      expect(store.tones.map((t) => t.id).toList(), reversed);
    });
  });

  group('ConfigStore audiences', () {
    test('upsertAudience creates a new audience', () async {
      await store.upsertAudience(
        const AudienceTag(id: 'stakeholders', label: 'stakeholders'),
      );
      expect(store.audiences.map((a) => a.id), contains('stakeholders'));
    });

    test('hideAudience hides a built-in and deletes a custom one', () async {
      await store.hideAudience('coworkers');
      expect(store.audiences.map((a) => a.id), isNot(contains('coworkers')));

      await store.upsertAudience(
        const AudienceTag(id: 'temp', label: 'temp'),
      );
      await store.hideAudience('temp');
      expect(store.audiences.map((a) => a.id), isNot(contains('temp')));
    });

    test('resetAudienceToDefault restores an edited built-in to its seed content', () async {
      await store.upsertAudience(
        const AudienceTag(id: 'coworkers', label: 'my team'),
      );
      expect(
        store.audiences.firstWhere((a) => a.id == 'coworkers').label,
        'my team',
      );

      await store.resetAudienceToDefault('coworkers');

      expect(
        store.audiences.firstWhere((a) => a.id == 'coworkers').label,
        'coworkers',
      );
    });

    test('resetAudienceToDefault un-hides a hidden built-in', () async {
      await store.hideAudience('coworkers');
      expect(store.audiences.map((a) => a.id), isNot(contains('coworkers')));

      await store.resetAudienceToDefault('coworkers');

      expect(store.audiences.map((a) => a.id), contains('coworkers'));
    });

    test('resetAudienceToDefault is a no-op for an audience with no built-in to reset to', () async {
      await store.upsertAudience(const AudienceTag(id: 'custom_aud', label: 'Custom'));

      await store.resetAudienceToDefault('custom_aud');

      expect(
        store.audiences.firstWhere((a) => a.id == 'custom_aud').label,
        'Custom',
      );
    });

    test('reorderAudiences changes the order audiences are returned in', () async {
      final ids = store.audiences.map((a) => a.id).toList();
      final reversed = ids.reversed.toList();

      await store.reorderAudiences(reversed);

      expect(store.audiences.map((a) => a.id).toList(), reversed);
    });
  });

  group('ConfigStore.audienceById', () {
    test('returns the matching audience', () {
      expect(store.audienceById('coworkers').label, 'coworkers');
    });

    test('synthesises a placeholder for an unknown id, not the first audience', () {
      final placeholder = store.audienceById('a-deleted-audience-id');
      expect(placeholder.id, 'a-deleted-audience-id');
      expect(placeholder.label, 'a-deleted-audience-id');
    });

    test('resolves the current label after a rename — the id/label bug fix', () async {
      // Before the audience editor existed, RewriteRequest.audience stored
      // labels directly, which only worked because every built-in had
      // id == label. Renaming must not orphan anything still holding the id.
      await store.upsertAudience(
        const AudienceTag(id: 'coworkers', label: 'my team'),
      );
      expect(store.audienceById('coworkers').label, 'my team');
    });
  });

  group('ConfigStore.hiddenAudiences', () {
    test('lists a hidden built-in so it can be brought back', () async {
      await store.hideAudience('coworkers');
      final hidden = await store.hiddenAudiences();
      expect(hidden.map((a) => a.id), contains('coworkers'));
    });

    test('is empty when nothing is hidden', () async {
      expect(await store.hiddenAudiences(), isEmpty);
    });
  });
}
