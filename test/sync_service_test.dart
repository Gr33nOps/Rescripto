import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rescripto/services/backup/backup_service.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:rescripto/services/settings_service.dart';
import 'package:rescripto/services/storage_service.dart';
import 'package:rescripto/services/sync/sync_service.dart';
import 'package:rescripto/services/sync/webdav_client.dart';
import 'package:rescripto/services/sync/webdav_exception.dart';
import 'package:rescripto/services/workflows/workflow_registry.dart';
import 'package:rescripto/services/workflows/workflow_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late SettingsService settings;
  late CredentialStore credentialStore;
  late BackupService backupService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_sync_service');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    final configStore = ConfigStore(database);
    await configStore.load();
    final workflowRegistry = WorkflowRegistry(WorkflowStore(database));
    await workflowRegistry.load();
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    final providerRegistry = ProviderRegistry(ProviderStore(database, credentialStore));
    await providerRegistry.load();
    backupService = BackupService(
      settings: settings,
      configStore: configStore,
      workflowRegistry: workflowRegistry,
      providerRegistry: providerRegistry,
      storage: StorageService(database),
      credentialStore: credentialStore,
    );
    await settings.setWebdavUrl('https://cloud.example.com/dav/files/me');
    await settings.setWebdavUsername('alice');
    await credentialStore.write(SyncService.passwordRef, 'server-password');
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  SyncService buildService(Future<http.Response> Function(http.Request) handler) {
    return SyncService(
      settings: settings,
      backupService: backupService,
      credentialStore: credentialStore,
      client: WebDavClient(MockClient(handler)),
    );
  }

  group('SyncService.isConfigured', () {
    test('false before a server URL is set', () async {
      await settings.setWebdavUrl(null);
      final service = buildService((_) async => http.Response('', 200));
      expect(service.isConfigured, isFalse);
    });

    test('true once a server URL is set', () {
      final service = buildService((_) async => http.Response('', 200));
      expect(service.isConfigured, isTrue);
    });
  });

  group('SyncService.push', () {
    test('PUTs the encrypted bundle to <base>/rescripto-sync.rescriptobackup and records the push time', () async {
      http.Request? captured;
      final service = buildService((request) async {
        captured = request;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await service.push('a passphrase');

      expect(captured!.method, 'PUT');
      expect(captured!.url.toString(), 'https://cloud.example.com/dav/files/me/rescripto-sync.rescriptobackup');
      expect(captured!.bodyBytes, isNotEmpty);
      expect(settings.lastSyncPushAt, isNotNull);
    });

    test('throws before making a request if no server password is configured', () async {
      await credentialStore.delete(SyncService.passwordRef);
      final service = buildService((_) async => http.Response('', 200));

      await expectLater(
        service.push('a passphrase'),
        throwsA(isA<WebDavException>().having((e) => e.isAuthFailure, 'isAuthFailure', isTrue)),
      );
    });
  });

  group('SyncService.pull', () {
    test('GETs and decrypts the remote bundle', () async {
      // First push through a real service so the fixture bytes are a
      // genuine encrypted bundle, not hand-rolled ciphertext.
      Uint8List? uploaded;
      final pushService = buildService((request) async {
        uploaded = request.bodyBytes;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');
      await pushService.push('shared passphrase');

      final pullService = buildService((request) async => http.Response.bytes(uploaded!, 200));
      final bundle = await pullService.pull('shared passphrase');

      expect(bundle.dbVersion, isNotNull);
    });

    test('throws WebDavException(404) when nothing has been synced yet', () async {
      final service = buildService((_) async => http.Response('', 404));
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(
        service.pull('a passphrase'),
        throwsA(isA<WebDavException>().having((e) => e.isNotFound, 'isNotFound', isTrue)),
      );
    });
  });

  group('SyncService.remoteNewerThanLastPush', () {
    test('returns null when nothing has been pushed to the server yet', () async {
      final service = buildService((_) async => http.Response('', 404));
      expect(await service.remoteNewerThanLastPush(), isNull);
    });

    test('returns the remote time when this device has never pushed but the server has a file', () async {
      final remoteTime = DateTime.utc(2026, 1, 1);
      final service = buildService((_) async => http.Response('''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat><D:prop>
<D:getlastmodified>${HttpDate.format(remoteTime)}</D:getlastmodified>
</D:prop></D:propstat></D:response></D:multistatus>
''', 207));

      expect(await service.remoteNewerThanLastPush(), remoteTime);
    });

    test('returns null when the server is not ahead of the last push', () async {
      final pushTime = DateTime.utc(2026, 6, 1);
      await settings.setLastSyncPushAt(pushTime);
      final service = buildService((_) async => http.Response('''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat><D:prop>
<D:getlastmodified>${HttpDate.format(pushTime)}</D:getlastmodified>
</D:prop></D:propstat></D:response></D:multistatus>
''', 207));

      expect(await service.remoteNewerThanLastPush(), isNull);
    });

    test('returns the remote time when the server is ahead of the last push', () async {
      await settings.setLastSyncPushAt(DateTime.utc(2026, 1, 1));
      final remoteTime = DateTime.utc(2026, 6, 1);
      final service = buildService((_) async => http.Response('''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat><D:prop>
<D:getlastmodified>${HttpDate.format(remoteTime)}</D:getlastmodified>
</D:prop></D:propstat></D:response></D:multistatus>
''', 207));

      expect(await service.remoteNewerThanLastPush(), remoteTime);
    });
  });
}
