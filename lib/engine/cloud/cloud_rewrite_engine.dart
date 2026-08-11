import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/provider_config.dart';
import '../../models/rewrite_output.dart';
import '../../services/credentials/credential_store.dart';
import '../../services/network/network_feature.dart';
import '../../services/network/network_guard.dart';
import '../../services/providers/provider_registry.dart';
import '../engine_capabilities.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import '../engine_stage.dart';
import '../engine_target.dart';
import '../generation_handle.dart';
import '../rewrite_engine.dart';
import 'chat_protocol.dart';
import 'cloud_error_mapper.dart';
import 'sse_decoder.dart';

/// A [RewriteEngine] parameterised by [ChatProtocol] — one instance per
/// protocol serves every provider that speaks it, since which provider,
/// credential, and base URL to use for a given call arrives on the request
/// itself (`EngineTarget.providerId`), not on the engine. This deliberately
/// mirrors `LocalLlmEngine`/`ChatTemplate.forFamily`, the same "one engine,
/// pluggable shape" pattern already proven for local models.
///
/// Nothing here is stashed between [prepare] and [start] the way
/// `LocalLlmEngine._preparedTemplate` is — that wart only works because
/// there's exactly one local engine instance for exactly one model at a
/// time. A cloud protocol engine serves many providers, sometimes
/// concurrently from the app's perspective, so every call resolves its own
/// `ProviderConfig` fresh from `request.target.providerId`.
class CloudRewriteEngine implements RewriteEngine {
  CloudRewriteEngine(
    this.id,
    this.protocol,
    this._providerRegistry,
    this._credentialStore,
    this._networkGuard, {
    this.errorMapper = const CloudErrorMapper(),
    this.sseDecoder = const SseDecoder(),
    this.idleTimeout = const Duration(seconds: 45),
  });

  @override
  final String id;

  final ChatProtocol protocol;
  final CloudErrorMapper errorMapper;
  final SseDecoder sseDecoder;

  /// How long to wait for the *next* SSE event before giving up on a stalled
  /// connection. Deliberately not a Dio `receiveTimeout` — that would apply
  /// to the whole response and kill a long but healthy rewrite mid-stream.
  final Duration idleTimeout;

  final ProviderRegistry _providerRegistry;
  final CredentialStore _credentialStore;
  final NetworkGuard _networkGuard;

  @override
  EngineCapabilities get capabilities =>
      const EngineCapabilities(needsLocalInstall: false, requiresNetwork: true);

  /// A no-op beyond validating [target] resolves to an enabled, configured
  /// provider — cloud has no model to load. Deliberately discards the
  /// resolved config rather than caching it; see the class doc.
  @override
  Future<void> prepare(EngineTarget target) async {
    _resolveConfig(target);
  }

  @override
  GenerationHandle start(EngineRequest request) {
    final cancelToken = CancelToken();
    final handle = StreamGenerationHandle(
      onCancel: () async => cancelToken.cancel('Cancelled by user.'),
    );
    unawaited(_run(handle, request, cancelToken));
    return handle;
  }

  ProviderConfig _resolveConfig(EngineTarget target) {
    final providerId = target.providerId;
    final config = providerId == null ? null : _providerRegistry.byId(providerId);
    if (config == null || !config.enabled) {
      throw ProviderNotConfiguredException(providerId ?? target.engineId);
    }
    return config;
  }

  Future<void> _run(
    StreamGenerationHandle handle,
    EngineRequest request,
    CancelToken cancelToken,
  ) async {
    final ProviderConfig config;
    try {
      handle.emitStage(EngineStage.submitting);
      config = _resolveConfig(request.target);
    } on EngineException catch (e) {
      handle.completeError(e);
      return;
    }

    try {
      final modelRef = request.target.modelRef;
      final secret = await _credentialStore.read(config.credential);
      if (secret == null && config.preset.requiresKey) {
        handle.completeError(ProviderNotConfiguredException(config.id));
        return;
      }

      final headers = {
        ...protocol.headers(config),
        if (secret != null) ...Map.fromEntries([protocol.authHeader(config, secret)]),
      };
      final uri = protocol.pathFor(config, modelRef);
      final requestBody = protocol.body(config, request, modelRef);

      final dio = _networkGuard.dioFor(
        NetworkFeature.cloudRewrite,
        purpose: 'Cloud rewrite via ${config.displayName}',
      );

      final response = await dio.post<ResponseBody>(
        uri.toString(),
        data: jsonEncode(requestBody),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          // Classify a bad status from the real decoded body rather than
          // letting Dio throw with a raw, undecoded stream object attached.
          validateStatus: (_) => true,
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          // No receiveTimeout — it would cut off a long but healthy rewrite.
          // The idle-event watchdog below covers a genuinely stalled stream.
        ),
        cancelToken: cancelToken,
      );

      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status < 200 || status >= 300 || body == null) {
        final decoded = await _drainAsJson(body?.stream);
        handle.completeError(
          errorMapper.mapStatusCode(
            status,
            decoded,
            provider: config,
            protocol: protocol,
            headers: response.headers,
          ),
        );
        return;
      }

      handle.emitStage(EngineStage.streaming);
      final buffer = StringBuffer();
      final events = StreamIterator(sseDecoder.decode(body.stream));
      try {
        while (await events.moveNext().timeout(idleTimeout)) {
          if (handle.isCancelled) break;
          final chunk = protocol.decode(events.current);
          switch (chunk) {
            case null:
              break;
            case TextProtocolChunk(:final text):
              buffer.write(text);
              handle.emitDelta(text);
            case DoneProtocolChunk():
              // Keep draining — some providers still send a trailing event
              // or two after the one that reports completion — but nothing
              // else to record.
              break;
            case ErrorProtocolChunk(:final error):
              handle.completeError(error);
              return;
          }
        }
      } finally {
        await events.cancel();
      }

      if (handle.isCancelled) {
        handle.completeError(const GenerationCancelledException());
        return;
      }

      handle.emitStage(EngineStage.finalizing);
      final text = buffer.toString();
      if (text.isEmpty) {
        handle.completeError(const EmptyResponseException());
      } else {
        handle.complete(RewriteOutput(text: text));
      }
    } catch (e) {
      if (handle.isCancelled) {
        handle.completeError(const GenerationCancelledException());
      } else if (e is TimeoutException) {
        handle.completeError(const NetworkUnavailableException());
      } else {
        handle.completeError(errorMapper.map(e, provider: config, protocol: protocol));
      }
    }
  }

  Future<Object?> _drainAsJson(Stream<List<int>>? stream) async {
    if (stream == null) return null;
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {}
}
