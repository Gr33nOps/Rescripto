import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late FakeSecureStorage storage;
  late CredentialStore store;

  const openAiKey = CredentialRef(providerId: 'openai', kind: CredentialKind.apiKey);
  const anthropicKey = CredentialRef(providerId: 'anthropic', kind: CredentialKind.apiKey);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rescripto_credentials');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    storage = FakeSecureStorage();
    store = CredentialStore(database, storage: storage);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('CredentialStore.write / read / has', () {
    test('a written secret round-trips', () async {
      await store.write(openAiKey, 'sk-test-123', label: 'Personal');
      expect(await store.read(openAiKey), 'sk-test-123');
      expect(await store.has(openAiKey), isTrue);
    });

    test('an unwritten ref is absent, not an error', () async {
      expect(await store.read(openAiKey), isNull);
      expect(await store.has(openAiKey), isFalse);
    });

    test('two different providers never collide', () async {
      await store.write(openAiKey, 'openai-secret');
      await store.write(anthropicKey, 'anthropic-secret');
      expect(await store.read(openAiKey), 'openai-secret');
      expect(await store.read(anthropicKey), 'anthropic-secret');
    });

    test('two accounts for the same provider never collide', () async {
      const personal = CredentialRef(
        providerId: 'openai',
        accountId: 'personal',
        kind: CredentialKind.apiKey,
      );
      const work = CredentialRef(
        providerId: 'openai',
        accountId: 'work',
        kind: CredentialKind.apiKey,
      );
      await store.write(personal, 'personal-key');
      await store.write(work, 'work-key');
      expect(await store.read(personal), 'personal-key');
      expect(await store.read(work), 'work-key');
    });

    test('writing again overwrites rather than duplicating the index row', () async {
      await store.write(openAiKey, 'first');
      await store.write(openAiKey, 'second');
      expect(await store.read(openAiKey), 'second');
      expect(await store.listRefs(), hasLength(1));
    });

    test('rolls back the Keystore write if indexing it fails', () async {
      // Regression coverage: write() used to leave the Keystore write in
      // place even when the index insert that follows it failed — the
      // secret existed but every read() and has() call (which only look at
      // the index) reported the ref as "not configured", making the secret
      // permanently unreachable through the app's own API without ever
      // being deleted.
      final db = await database.db;
      await db.execute('DROP TABLE credential_ref');

      await expectLater(store.write(openAiKey, 'sk-orphan-risk'), throwsA(anything));

      expect(storage.values, isEmpty, reason: 'the Keystore write must be rolled back');
    });
  });

  group('CredentialStore degrades gracefully on a broken Keystore', () {
    test('read returns null instead of throwing', () async {
      await store.write(openAiKey, 'sk-test-123');
      storage.broken = true;
      expect(await store.read(openAiKey), isNull);
    });
  });

  group('CredentialStore.delete', () {
    test('removes both the secret and the index row', () async {
      await store.write(openAiKey, 'sk-test-123');
      await store.delete(openAiKey);

      expect(await store.read(openAiKey), isNull);
      expect(await store.has(openAiKey), isFalse);
      expect(storage.values, isEmpty);
    });

    test('does not remove an unrelated ref', () async {
      await store.write(openAiKey, 'openai-secret');
      await store.write(anthropicKey, 'anthropic-secret');
      await store.delete(openAiKey);
      expect(await store.read(anthropicKey), 'anthropic-secret');
    });
  });

  group('CredentialStore.listRefs', () {
    test('never carries a secret value, only ids', () async {
      await store.write(openAiKey, 'sk-test-123', label: 'Personal');
      final refs = await store.listRefs();
      expect(refs, [openAiKey]);
      // The point of the ref type: nothing in it is the secret string.
      expect(refs.single.toString(), isNot(contains('sk-test-123')));
    });
  });

  group('CredentialStore.deleteAll', () {
    test('wipes every stored secret and clears the index', () async {
      await store.write(openAiKey, 'a');
      await store.write(anthropicKey, 'b');

      final removed = await store.deleteAll();

      expect(removed, 2);
      expect(await store.listRefs(), isEmpty);
      expect(storage.values, isEmpty);
    });

    test('also sweeps a key the index never knew about', () async {
      // Simulates a stray key from a prior format — present in the backend,
      // absent from the SQLite index. deleteAll's own SecureStorage.deleteAll
      // sweep is what catches this, not the per-ref loop.
      storage.values['cred.v0.legacy'] = 'orphan';
      await store.write(openAiKey, 'a');

      await store.deleteAll();

      expect(storage.values, isEmpty);
    });

    test('is idempotent', () async {
      await store.write(openAiKey, 'a');
      await store.deleteAll();
      final second = await store.deleteAll();
      expect(second, 0);
    });
  });

  group('credential_ref schema', () {
    test('has no column capable of holding a secret', () async {
      final db = await database.db;
      final columns = await db.rawQuery('PRAGMA table_info(credential_ref)');
      final names = columns.map((c) => c['name'] as String).toSet();

      expect(
        names,
        {'provider_id', 'account_id', 'kind', 'label', 'created_at'},
      );
      // No plausible name for a secret column exists here at all — this is
      // the structural guarantee, not a naming convention to remember.
      for (final name in names) {
        expect(name, isNot(contains('secret')));
        expect(name, isNot(contains('key')));
        expect(name, isNot(contains('token')));
        expect(name, isNot(contains('password')));
      }
    });
  });
}
