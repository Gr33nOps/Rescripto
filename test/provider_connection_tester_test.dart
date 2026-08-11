import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_guard.dart';
import 'package:rescripto/services/network/network_log.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:rescripto/services/providers/provider_connection_tester.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

class _FixedStatusAdapter implements HttpClientAdapter {
  _FixedStatusAdapter(this.statusCode);
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(const [], statusCode);
  }

  @override
  void close({bool force = false}) {}
}

ProviderConfig _config(String presetId, String id) {
  final now = DateTime.now();
  return ProviderConfig(
    id: id,
    presetId: presetId,
    displayName: presetId,
    credential: CredentialRef(providerId: id, kind: CredentialKind.apiKey),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late CredentialStore credentialStore;
  late NetworkPolicy policy;
  late NetworkLog log;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_connection_tester');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    SharedPreferences.setMockInitialValues({});
    policy = NetworkPolicy();
    await policy.init();
    await policy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
    log = NetworkLog(database);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  test('a 200 response is a successful test', () async {
    final config = _config('openai', 'openai-1');
    await credentialStore.write(config.credential, 'sk-test');
    final adapter = _FixedStatusAdapter(200);
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final tester = ProviderConnectionTester(guard, credentialStore);

    await tester.test(config); // completes without throwing
  });

  test('a 401 response throws ProviderAuthException', () async {
    final config = _config('openai', 'openai-1');
    await credentialStore.write(config.credential, 'sk-bad');
    final adapter = _FixedStatusAdapter(401);
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final tester = ProviderConnectionTester(guard, credentialStore);

    await expectLater(tester.test(config), throwsA(isA<ProviderAuthException>()));
  });

  test('throws ProviderNotConfiguredException when no key is stored', () async {
    final config = _config('openai', 'openai-1');
    final adapter = _FixedStatusAdapter(200);
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final tester = ProviderConnectionTester(guard, credentialStore);

    await expectLater(
      tester.test(config),
      throwsA(isA<ProviderNotConfiguredException>()),
    );
  });

  test('gemini sends the key as a header, never as a ?key= query parameter', () async {
    final config = _config('gemini', 'gemini-1');
    await credentialStore.write(config.credential, 'gm-test-key');
    final adapter = _FixedStatusAdapter(200);
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final tester = ProviderConnectionTester(guard, credentialStore);

    await tester.test(config);

    expect(adapter.lastRequest!.headers['x-goog-api-key'], 'gm-test-key');
    expect(adapter.lastRequest!.uri.queryParameters.keys, isNot(contains('key')));
  });

  test('anthropic sends the key as x-api-key, never Authorization', () async {
    final config = _config('anthropic', 'anthropic-1');
    await credentialStore.write(config.credential, 'sk-ant-test');
    final adapter = _FixedStatusAdapter(200);
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final tester = ProviderConnectionTester(guard, credentialStore);

    await tester.test(config);

    expect(adapter.lastRequest!.headers['x-api-key'], 'sk-ant-test');
    expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
  });
}
