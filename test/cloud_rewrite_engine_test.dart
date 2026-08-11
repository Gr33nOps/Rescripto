import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/cloud/anthropic_protocol.dart';
import 'package:rescripto/engine/cloud/cloud_rewrite_engine.dart';
import 'package:rescripto/engine/cloud/gemini_protocol.dart';
import 'package:rescripto/engine/cloud/openai_compatible_protocol.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_request.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/generation_handle.dart';
import 'package:rescripto/engine/prompt_spec.dart';
import 'package:rescripto/engine/generation_options.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_guard.dart';
import 'package:rescripto/services/network/network_log.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

/// Serves a scripted, chunked SSE response through Dio's transport seam —
/// the same technique `network_guard_test.dart` uses, extended to stream
/// bytes over time rather than resolve a single fixed response, and to
/// honour Dio's `cancelFuture` so a cancel test can observe a real abort.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({
    required this.statusCode,
    required this.chunks,
    this.chunkDelay,
  });

  final int statusCode;
  final List<List<int>> chunks;
  final Duration? chunkDelay;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    final controller = StreamController<Uint8List>();

    unawaited(() async {
      for (final chunk in chunks) {
        if (controller.isClosed) return;
        if (chunkDelay != null) await Future<void>.delayed(chunkDelay!);
        if (controller.isClosed) return;
        controller.add(Uint8List.fromList(chunk));
      }
      if (!controller.isClosed) await controller.close();
    }());

    cancelFuture?.then((_) {
      if (!controller.isClosed) {
        controller.addError(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
        controller.close();
      }
    });

    return ResponseBody(controller.stream, statusCode);
  }

  @override
  void close({bool force = false}) {}
}

List<int> _sse(String text) => utf8.encode(text);

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late CredentialStore credentialStore;
  late ProviderRegistry registry;
  late NetworkPolicy policy;
  late NetworkLog log;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_cloud_engine');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    registry = ProviderRegistry(ProviderStore(database, credentialStore));
    await registry.load();
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

  Future<ProviderConfig> configure(String presetId) async {
    final id = registry.newConfigId(presetId);
    final now = DateTime.now();
    final config = ProviderConfig(
      id: id,
      presetId: presetId,
      displayName: presetId,
      credential: CredentialRef(providerId: id, kind: CredentialKind.apiKey),
      createdAt: now,
      updatedAt: now,
    );
    await registry.save(config);
    await credentialStore.write(config.credential, 'test-secret-key');
    return config;
  }

  EngineRequest requestFor(ProviderConfig config, String modelRef) {
    return EngineRequest(
      target: config.targetFor(modelRef),
      prompt: const PromptSpec(system: 'Rewrite this.', user: 'hello world'),
      options: const GenerationOptions(),
    );
  }

  group('OpenAiCompatibleProtocol via CloudRewriteEngine', () {
    test('streams deltas and completes on [DONE]', () async {
      final config = await configure('openai');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [
          _sse('data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
              'data: {"choices":[{"delta":{"content":" there"}}]}\n\n'
              'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
              'data: [DONE]\n\n'),
        ],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.openaiCompatible',
        const OpenAiCompatibleProtocol(),
        registry,
        credentialStore,
        guard,
      );

      final target = config.targetFor('gpt-4o');
      await engine.prepare(target);
      final handle = engine.start(requestFor(config, 'gpt-4o'));
      final deltas = <String>[];
      handle.events.listen((e) {
        if (e is TokenDelta) deltas.add(e.delta);
      });

      final output = await handle.done;
      expect(output.text, 'Hello there');
      expect(deltas, ['Hello', ' there']);
      expect(adapter.lastRequest!.headers['Authorization'], 'Bearer test-secret-key');
    });

    test('finish_reason content_filter maps to ContentFilteredException', () async {
      final config = await configure('openai');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [
          _sse('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n'
              'data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}\n\n'),
        ],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.openaiCompatible',
        const OpenAiCompatibleProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gpt-4o'));
      final handle = engine.start(requestFor(config, 'gpt-4o'));

      await expectLater(handle.done, throwsA(isA<ContentFilteredException>()));
    });

    test('a non-2xx response is classified from the decoded body, not thrown as a raw stream', () async {
      final config = await configure('openai');
      final adapter = _ScriptedAdapter(
        statusCode: 401,
        chunks: [_sse('{"error":{"type":"invalid_api_key","code":"invalid_api_key"}}')],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.openaiCompatible',
        const OpenAiCompatibleProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gpt-4o'));
      final handle = engine.start(requestFor(config, 'gpt-4o'));

      await expectLater(handle.done, throwsA(isA<ProviderAuthException>()));
    });

    test('cancelling mid-stream surfaces GenerationCancelledException', () async {
      final config = await configure('openai');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunkDelay: const Duration(milliseconds: 50),
        chunks: List.generate(20, (_) => _sse(':keep-alive\n\n')),
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.openaiCompatible',
        const OpenAiCompatibleProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gpt-4o'));
      final handle = engine.start(requestFor(config, 'gpt-4o'));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await handle.cancel();

      await expectLater(handle.done, throwsA(isA<GenerationCancelledException>()));
    });
  });

  group('AnthropicProtocol via CloudRewriteEngine', () {
    test('streams deltas and completes on message_stop, with no [DONE]', () async {
      final config = await configure('anthropic');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [
          _sse('event: content_block_delta\n'
              'data: {"delta":{"type":"text_delta","text":"Hi"}}\n\n'
              'event: content_block_delta\n'
              'data: {"delta":{"type":"text_delta","text":" there"}}\n\n'
              'event: message_delta\n'
              'data: {"delta":{"stop_reason":"end_turn"}}\n\n'
              'event: message_stop\n'
              'data: {}\n\n'),
        ],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.anthropic',
        const AnthropicProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('claude-sonnet-4-20250514'));
      final handle = engine.start(requestFor(config, 'claude-sonnet-4-20250514'));

      final output = await handle.done;
      expect(output.text, 'Hi there');
      expect(adapter.lastRequest!.headers['x-api-key'], 'test-secret-key');
      expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
    });

    test('an event: error arriving on an HTTP 200 stream still surfaces as a failure', () async {
      final config = await configure('anthropic');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [
          _sse('event: content_block_delta\n'
              'data: {"delta":{"type":"text_delta","text":"Hi"}}\n\n'
              'event: error\n'
              'data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n\n'),
        ],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.anthropic',
        const AnthropicProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('claude-sonnet-4-20250514'));
      final handle = engine.start(requestFor(config, 'claude-sonnet-4-20250514'));

      await expectLater(handle.done, throwsA(isA<ProviderUnavailableException>()));
    });
  });

  group('GeminiProtocol via CloudRewriteEngine', () {
    test('streams deltas and completes when the body just closes, with no explicit terminator', () async {
      final config = await configure('gemini');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [
          _sse('data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}\n\n'
              'data: {"candidates":[{"content":{"parts":[{"text":" there"}]},"finishReason":"STOP"}]}\n\n'),
        ],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.gemini',
        const GeminiProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gemini-2.5-flash'));
      final handle = engine.start(requestFor(config, 'gemini-2.5-flash'));

      final output = await handle.done;
      expect(output.text, 'Hi there');
    });

    test('sends the key as a header, never as a ?key= query parameter', () async {
      final config = await configure('gemini');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [_sse('data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n')],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.gemini',
        const GeminiProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gemini-2.5-flash'));
      final handle = engine.start(requestFor(config, 'gemini-2.5-flash'));
      await handle.done;

      expect(adapter.lastRequest!.headers['x-goog-api-key'], 'test-secret-key');
      expect(adapter.lastRequest!.uri.queryParameters.keys, isNot(contains('key')));
    });

    test('SAFETY finish reason maps to ContentFilteredException', () async {
      final config = await configure('gemini');
      final adapter = _ScriptedAdapter(
        statusCode: 200,
        chunks: [_sse('data: {"candidates":[{"finishReason":"SAFETY"}]}\n\n')],
      );
      final guard = NetworkGuard(policy, log, adapterOverride: () => adapter);
      final engine = CloudRewriteEngine(
        'cloud.gemini',
        const GeminiProtocol(),
        registry,
        credentialStore,
        guard,
      );

      await engine.prepare(config.targetFor('gemini-2.5-flash'));
      final handle = engine.start(requestFor(config, 'gemini-2.5-flash'));

      await expectLater(handle.done, throwsA(isA<ContentFilteredException>()));
    });
  });

  group('CloudRewriteEngine.prepare', () {
    test('throws ProviderNotConfiguredException for a target with no matching provider', () async {
      final guard = NetworkGuard(policy, log);
      final engine = CloudRewriteEngine(
        'cloud.openaiCompatible',
        const OpenAiCompatibleProtocol(),
        registry,
        credentialStore,
        guard,
      );

      const target = EngineTarget(
        engineId: 'cloud.openaiCompatible',
        modelRef: 'gpt-4o',
        providerId: 'does-not-exist',
      );

      await expectLater(
        engine.prepare(target),
        throwsA(isA<ProviderNotConfiguredException>()),
      );
    });
  });
}
