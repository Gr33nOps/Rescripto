import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rescripto/models/network_log_entry.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_exceptions.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_guard.dart';
import 'package:rescripto/services/network/network_log.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stands in for Dio's real transport. Swapping `httpClientAdapter` — rather
/// than adding a second `Interceptor` that resolves early — is the seam that
/// actually matches how a real response arrives: a response resolved from
/// inside an `onRequest` callback short-circuits the chain and skips
/// `onResponse` for interceptors registered ahead of it, which silently
/// broke an earlier version of these tests (the guard's own `onResponse`,
/// where it closes the log entry with a status code, never ran). A response
/// that comes back from the adapter flows through every interceptor's
/// `onResponse`, same as it does in the app.
class _FakeAdapter implements HttpClientAdapter {
  static const _bytes = [1, 2, 3, 4, 5];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      _bytes,
      200,
      headers: {
        'content-length': ['${_bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Never actually dispatches — the guard's onRequest rejects before Dio's
/// transport layer is reached, so no real network access happens here.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._response);
  final http.StreamedResponse Function() _response;
  int sendCallCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCallCount++;
    return _response();
  }

  @override
  void close() {}
}

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late NetworkLog log;
  late NetworkPolicy policy;
  late NetworkGuard guard;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_network_guard');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    log = NetworkLog(database);
    SharedPreferences.setMockInitialValues({});
    policy = NetworkPolicy();
    await policy.init();
    guard = NetworkGuard(policy, log);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('NetworkGuard.dioFor', () {
    test('lets an allowed request through and logs it', () async {
      final dio = guard.dioFor(NetworkFeature.modelDownload, purpose: 'test');
      dio.httpClientAdapter = _FakeAdapter();

      final response = await dio.get('https://example.com/model.gguf');

      expect(response.statusCode, 200);
      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.allowed);
      expect(entry.statusCode, 200);
      expect(entry.purpose, 'test');
      expect(entry.bytesReceived, 5);
    });

    test('rejects before dispatch when the feature is disabled', () async {
      final dio = guard.dioFor(NetworkFeature.cloudRewrite);
      var reachedTransport = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            reachedTransport = true;
            handler.next(options);
          },
        ),
      );

      await expectLater(
        dio.get('https://api.openai.com/v1/models'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<NetworkBlockedByPolicyException>().having(
              (e) => e.reason,
              'reason',
              NetworkBlockReason.featureDisabled,
            ),
          ),
        ),
      );
      expect(reachedTransport, isFalse);

      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.blockedByPolicy);
    });

    test('rejects every feature when the kill switch is on', () async {
      await policy.setKillSwitch(true);
      final dio = guard.dioFor(NetworkFeature.modelDownload);

      await expectLater(
        dio.get('https://huggingface.co/model.gguf'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<NetworkBlockedByPolicyException>().having(
              (e) => e.reason,
              'reason',
              NetworkBlockReason.killSwitch,
            ),
          ),
        ),
      );

      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.blockedByKillSwitch);
    });

    test('rejects a cloudRewrite request carrying a secret in its query string', () async {
      await policy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      final dio = guard.dioFor(NetworkFeature.cloudRewrite);

      await expectLater(
        dio.get('https://generativelanguage.googleapis.com/v1/models?key=abc123'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<NetworkBlockedByPolicyException>().having(
              (e) => e.reason,
              'reason',
              NetworkBlockReason.secretInUrl,
            ),
          ),
        ),
      );
    });

    test('does not reject the same query param name for a feature other than cloudRewrite', () async {
      // The secret-in-URL check is scoped to cloudRewrite; modelDownload's
      // Hugging Face URLs are never expected to carry one, and the check
      // should not become a surprise failure mode for unrelated features.
      final dio = guard.dioFor(NetworkFeature.modelDownload);
      dio.httpClientAdapter = _FakeAdapter();
      final response = await dio.get('https://huggingface.co/model?key=not-a-secret-here');
      expect(response.statusCode, 200);
    });
  });

  group('NetworkGuard.httpClientFor', () {
    http.StreamedResponse fakeResponse() => http.StreamedResponse(
      Stream.fromIterable([utf8.encode('hello')]),
      200,
      contentLength: 5,
    );

    test('lets an allowed request through, delegates to the inner client, and logs it', () async {
      final inner = _FakeHttpClient(fakeResponse);
      final client = GuardedHttpClient(
        feature: NetworkFeature.voiceModelDownload,
        policy: policy,
        log: log,
        purpose: 'voice model',
        inner: inner,
      );

      final response = await client.get(Uri.parse('https://example.com/ggml-base.bin'));

      expect(response.statusCode, 200);
      expect(inner.sendCallCount, 1);
      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.allowed);
      expect(entry.purpose, 'voice model');
      expect(entry.bytesReceived, 5);
    });

    test('blocks before ever calling the inner client when disabled', () async {
      final inner = _FakeHttpClient(fakeResponse);
      final client = GuardedHttpClient(
        feature: NetworkFeature.cloudSpeech,
        policy: policy,
        log: log,
        inner: inner,
      );

      await expectLater(
        client.get(Uri.parse('https://example.com/transcribe')),
        throwsA(isA<NetworkBlockedByPolicyException>()),
      );
      expect(inner.sendCallCount, 0);

      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.blockedByPolicy);
    });

    test('blocks on the kill switch too', () async {
      await policy.setKillSwitch(true);
      final inner = _FakeHttpClient(fakeResponse);
      final client = GuardedHttpClient(
        feature: NetworkFeature.voiceModelDownload,
        policy: policy,
        log: log,
        inner: inner,
      );

      await expectLater(
        client.get(Uri.parse('https://example.com/ggml-base.bin')),
        throwsA(
          isA<NetworkBlockedByPolicyException>().having(
            (e) => e.reason,
            'reason',
            NetworkBlockReason.killSwitch,
          ),
        ),
      );
      expect(inner.sendCallCount, 0);
    });
  });
}
