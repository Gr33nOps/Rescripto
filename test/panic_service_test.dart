import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:rescripto/services/panic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late CredentialStore credentialStore;
  late NetworkPolicy networkPolicy;
  late PanicService panicService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_panic');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    SharedPreferences.setMockInitialValues({});
    networkPolicy = NetworkPolicy();
    await networkPolicy.init();
    panicService = PanicService(credentialStore, networkPolicy);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('PanicService.wipeCredentials', () {
    test('turns the network kill switch on', () async {
      expect(networkPolicy.killSwitch, isFalse);
      await panicService.wipeCredentials();
      expect(networkPolicy.killSwitch, isTrue);
    });

    test('removes every stored credential and reports how many', () async {
      await credentialStore.write(
        const CredentialRef(providerId: 'openai', kind: CredentialKind.apiKey),
        'sk-1',
      );
      await credentialStore.write(
        const CredentialRef(providerId: 'anthropic', kind: CredentialKind.apiKey),
        'sk-2',
      );

      final report = await panicService.wipeCredentials();

      expect(report.credentialsWiped, 2);
      expect(report.networkDisabled, isTrue);
      expect(await credentialStore.listRefs(), isEmpty);
    });

    test('is safe to call with nothing stored', () async {
      final report = await panicService.wipeCredentials();
      expect(report.credentialsWiped, 0);
    });

    test('is idempotent', () async {
      await credentialStore.write(
        const CredentialRef(providerId: 'openai', kind: CredentialKind.apiKey),
        'sk-1',
      );
      await panicService.wipeCredentials();
      final second = await panicService.wipeCredentials();
      expect(second.credentialsWiped, 0);
      expect(networkPolicy.killSwitch, isTrue);
    });
  });
}
