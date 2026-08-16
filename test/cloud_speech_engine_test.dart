import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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
import 'package:rescripto/speech/cloud_speech_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

/// Serves a fixed JSON response for the transcription POST, over the same
/// Dio `httpClientAdapter` swap `network_guard_test.dart` establishes.
class _FixedJsonAdapter implements HttpClientAdapter {
  _FixedJsonAdapter({required this.statusCode, required this.json});

  final int statusCode;
  final Map<String, Object?> json;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    final bytes = utf8.encode(jsonEncode(json));
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase database;
  late CredentialStore credentialStore;
  late NetworkPolicy policy;
  late NetworkLog log;
  late File wavFile;
  late ProviderConfig provider;

  const channel = MethodChannel('flutter_whisper');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_cloud_speech');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    SharedPreferences.setMockInitialValues({});
    policy = NetworkPolicy();
    await policy.init();
    await policy.setFeatureEnabled(NetworkFeature.cloudSpeech, true);
    log = NetworkLog(database);

    wavFile = File('${tempDir.path}${Platform.pathSeparator}recording.wav')
      ..writeAsBytesSync([0, 1, 2, 3]);

    final now = DateTime.now();
    provider = ProviderConfig(
      id: 'openai-speech-1',
      presetId: 'openai',
      displayName: 'OpenAI',
      credential: const CredentialRef(providerId: 'openai-speech-1', kind: CredentialKind.apiKey),
      createdAt: now,
      updatedAt: now,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'startRecording' => null,
        'stopRecording' => wavFile.path,
        _ => null,
      },
    );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('uploads the recording and returns the transcribed text', () async {
    await credentialStore.write(provider.credential, 'sk-test');
    final adapter = _FixedJsonAdapter(statusCode: 200, json: {'text': 'hello world'});
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    final result = await engine.stopAndTranscribe();

    expect(result.text, 'hello world');
    expect(adapter.lastRequest!.headers['Authorization'], 'Bearer sk-test');
    expect(adapter.lastRequest!.uri.path, endsWith('/audio/transcriptions'));
  });

  test('deletes the recorded file after a successful upload', () async {
    await credentialStore.write(provider.credential, 'sk-test');
    final adapter = _FixedJsonAdapter(statusCode: 200, json: {'text': 'ok'});
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    await engine.stopAndTranscribe();

    expect(wavFile.existsSync(), isFalse);
  });

  test('throws ProviderNotConfiguredException when no credential is stored', () async {
    final adapter = _FixedJsonAdapter(statusCode: 200, json: {'text': 'unused'});
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    await expectLater(
      engine.stopAndTranscribe(),
      throwsA(isA<ProviderNotConfiguredException>()),
    );
    // The recording is still cleaned up even though the upload never happened.
    expect(wavFile.existsSync(), isFalse);
  });

  test('checks the cloud credential before recording starts', () async {
    final guard = NetworkGuard(
      policy,
      log,
      adapterOverride: () => _FixedJsonAdapter(
        statusCode: 200,
        json: {'text': 'unused'},
      ),
    );
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await expectLater(
      engine.prepare(),
      throwsA(isA<ProviderNotConfiguredException>()),
    );
  });

  test('cancel stops recording and deletes the file without uploading', () async {
    await credentialStore.write(provider.credential, 'sk-test');
    final adapter = _FixedJsonAdapter(statusCode: 200, json: {'text': 'unused'});
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    await engine.cancel();

    expect(wavFile.existsSync(), isFalse);
    expect(adapter.lastRequest, isNull);
  });

  test('maps provider authentication failures instead of hiding them', () async {
    await credentialStore.write(provider.credential, 'sk-test');
    final adapter = _FixedJsonAdapter(statusCode: 401, json: {
      'error': {'message': 'invalid api key'},
    });
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    await expectLater(
      engine.stopAndTranscribe(),
      throwsA(isA<ProviderAuthException>()),
    );
    expect(wavFile.existsSync(), isFalse);
  });

  test('rejects an empty provider transcript', () async {
    await credentialStore.write(provider.credential, 'sk-test');
    final adapter = _FixedJsonAdapter(statusCode: 200, json: {'text': ''});
    final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
    final engine = CloudSpeechEngine(provider, credentialStore, guard);

    await engine.startRecording();
    await expectLater(
      engine.stopAndTranscribe(),
      throwsA(isA<EmptyResponseException>()),
    );
    expect(wavFile.existsSync(), isFalse);
  });
}
