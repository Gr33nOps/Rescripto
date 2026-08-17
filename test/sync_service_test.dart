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
import 'package:rescripto/services/sync/webdav_sync_conflict_exception.dart';
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
      // push() now PROPFINDs before (and after) the PUT to check for/record
      // a conflict — see the "conflict protection" group below. A 404
      // response means "nothing there yet", so this is a plain first push.
      http.Request? captured;
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') return http.Response('', 404);
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
        if (request.method == 'PROPFIND') return http.Response('', 404);
        uploaded = request.bodyBytes;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');
      await pushService.push('shared passphrase');

      // pull() also PROPFINDs, after the GET, to record the confirmed
      // remote state — see the "conflict protection" group below.
      final pullService = buildService((request) async {
        if (request.method == 'PROPFIND') return http.Response('', 404);
        return http.Response.bytes(uploaded!, 200);
      });
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

  group('SyncService.push — conflict protection', () {
    // Regression coverage: push() used to PUT unconditionally, so Device A
    // pushing after Device B's newer push landed would silently overwrite
    // B's data — the "server has a newer copy" banner was purely advisory.

    String propfindWithEtag(String etag, {DateTime? lastModified}) => '''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat><D:prop>
${lastModified != null ? '<D:getlastmodified>${HttpDate.format(lastModified)}</D:getlastmodified>' : ''}
<D:getetag>$etag</D:getetag>
</D:prop></D:propstat></D:response></D:multistatus>
''';

    test('throws WebDavSyncConflictException and never PUTs when the remote ETag has moved on', () async {
      await settings.setLastSyncEtag('"old-etag"');
      var putCalled = false;
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(propfindWithEtag('"new-etag-from-another-device"'), 207);
        }
        putCalled = true;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(service.push('a passphrase'), throwsA(isA<WebDavSyncConflictException>()));
      expect(putCalled, isFalse, reason: 'a detected conflict must never reach the PUT');
    });

    test('proceeds when the remote ETag matches what this device last confirmed', () async {
      await settings.setLastSyncEtag('"same-etag"');
      http.Request? putRequest;
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(propfindWithEtag('"same-etag"'), 207);
        }
        putRequest = request;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await service.push('a passphrase');

      expect(putRequest, isNotNull);
      expect(putRequest!.headers['If-Match'], '"same-etag"');
    });

    test('force: true overwrites despite a conflicting ETag', () async {
      await settings.setLastSyncEtag('"old-etag"');
      var putCalled = false;
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(propfindWithEtag('"new-etag-from-another-device"'), 207);
        }
        putCalled = true;
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await service.push('a passphrase', force: true);

      expect(putCalled, isTrue);
    });

    test('falls back to a timestamp comparison when the server has no ETag', () async {
      await settings.setLastKnownRemoteAt(DateTime.utc(2026, 1, 1));
      final newerRemoteTime = DateTime.utc(2026, 6, 1);
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response('''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat><D:prop>
<D:getlastmodified>${HttpDate.format(newerRemoteTime)}</D:getlastmodified>
</D:prop></D:propstat></D:response></D:multistatus>
''', 207);
        }
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(service.push('a passphrase'), throwsA(isA<WebDavSyncConflictException>()));
    });

    test('conflicts when the server already has a file but this device has never confirmed any state', () async {
      // A first sync from a device that has never pushed or pulled, onto a
      // server another device already populated — silently overwriting it
      // would be exactly the bug this whole check exists to prevent.
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(propfindWithEtag('"someone-elses-etag"', lastModified: DateTime.utc(2026, 1, 1)), 207);
        }
        return http.Response('', 201);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(service.push('a passphrase'), throwsA(isA<WebDavSyncConflictException>()));
    });

    test('pull records the remote state so this device\'s next push does not self-conflict', () async {
      final remoteBytes = Uint8List.fromList([1, 2, 3]);
      final service = buildService((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(propfindWithEtag('"remote-etag"', lastModified: DateTime.utc(2026, 3, 1)), 207);
        }
        return http.Response.bytes(remoteBytes, 200);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      // The bytes aren't a real encrypted bundle, so decrypt() throws —
      // irrelevant here, only the state recorded before that matters.
      await expectLater(service.pull('a passphrase'), throwsA(anything));

      expect(settings.lastSyncEtag, '"remote-etag"');
      expect(settings.lastKnownRemoteAt, DateTime.utc(2026, 3, 1));
    });
  });

  group('SyncService.testConnection', () {
    test('checks the given URL/username without persisting them', () async {
      http.Request? captured;
      final service = buildService((request) async {
        captured = request;
        return http.Response('', 404);
      });
      await credentialStore.write(SyncService.passwordRef, 'server-password');
      final urlBefore = settings.webdavUrl;
      final usernameBefore = settings.webdavUsername;

      await service.testConnection('https://other.example.com/dav/files/bob', 'bob');

      expect(captured!.url.toString(), 'https://other.example.com/dav/files/bob/rescripto-sync.rescriptobackup');
      expect(settings.webdavUrl, urlBefore, reason: 'testConnection must never write settings');
      expect(settings.webdavUsername, usernameBefore, reason: 'testConnection must never write settings');
    });

    test('rejects a malformed server URL with a typed exception instead of an uncaught FormatException', () async {
      final service = buildService((_) async => http.Response('', 200));
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(service.testConnection('not a url', 'bob'), throwsA(isA<WebDavException>()));
    });
  });

  group('SyncService — malformed server URL', () {
    test('push throws WebDavException instead of an uncaught FormatException', () async {
      await settings.setWebdavUrl('not a valid url');
      final service = buildService((_) async => http.Response('', 200));
      await credentialStore.write(SyncService.passwordRef, 'server-password');

      await expectLater(service.push('a passphrase'), throwsA(isA<WebDavException>()));
    });
  });
}
