import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/network_log_entry.dart';
import 'network_exceptions.dart';
import 'network_feature.dart';
import 'network_log.dart';
import 'network_policy.dart';

/// Query parameter names a `cloudRewrite` request must never carry. Several
/// providers (Gemini, at least) accept an API key this way; this app refuses
/// to send one, forcing header auth instead — and refuses to even log the
/// URL if it sees one, since the log is exactly where a leaked key would end
/// up otherwise.
const _secretQueryParams = {'key', 'api_key', 'access_token', 'token'};

/// The only sanctioned way to obtain a network client anywhere in this app.
///
/// Every call is checked against [NetworkPolicy] before it leaves the
/// device and recorded in [NetworkLog] — one row per request, opened before
/// dispatch and closed on completion. `ModelManager` and `flutter_whisper`'s
/// downloader are the only two callers today; see their wiring in
/// `app_providers.dart`.
///
/// This is a guarantee about Dart-initiated traffic, not a stronger one:
/// `libllama.so` and `libwhisper.so` make no network calls of their own today
/// (verified by grepping the vendored sources for socket/curl symbols — there
/// are none), but nothing here could stop native code that did. The only
/// mechanism that strong is not holding the `INTERNET` permission at all.
class NetworkGuard {
  NetworkGuard(this._policy, this._log, {@visibleForTesting this.adapterOverride});

  final NetworkPolicy _policy;
  final NetworkLog _log;

  /// Replaces every [Dio] instance's transport with a fake one, for tests.
  /// `ModelManager`/`GuardedHttpClient` callers hand the test their own `Dio`
  /// to swap `httpClientAdapter` on directly (see `network_guard_test.dart`);
  /// a caller that builds its `Dio` internally — like `CloudRewriteEngine` —
  /// has no such handle, so this is the seam for those instead.
  @visibleForTesting
  final HttpClientAdapter Function()? adapterOverride;

  Dio dioFor(NetworkFeature feature, {String? purpose}) {
    final dio = Dio();
    dio.interceptors.add(_GuardInterceptor(feature, _policy, _log, purpose));
    final override = adapterOverride;
    if (override != null) dio.httpClientAdapter = override();
    return dio;
  }

  http.Client httpClientFor(NetworkFeature feature, {String? purpose}) {
    return GuardedHttpClient(
      feature: feature,
      policy: _policy,
      log: _log,
      purpose: purpose,
    );
  }
}

NetworkBlockReason? _checkPolicy(NetworkFeature feature, NetworkPolicy policy, Uri uri) {
  if (policy.killSwitch) return NetworkBlockReason.killSwitch;
  if (!policy.isAllowed(feature)) return NetworkBlockReason.featureDisabled;
  if (feature == NetworkFeature.cloudRewrite &&
      uri.queryParameters.keys.any(
        (k) => _secretQueryParams.contains(k.toLowerCase()),
      )) {
    return NetworkBlockReason.secretInUrl;
  }
  return null;
}

NetworkOutcome _outcomeFor(NetworkBlockReason reason) => switch (reason) {
  NetworkBlockReason.killSwitch => NetworkOutcome.blockedByKillSwitch,
  NetworkBlockReason.featureDisabled => NetworkOutcome.blockedByPolicy,
  NetworkBlockReason.secretInUrl => NetworkOutcome.blockedByPolicy,
};

class _GuardInterceptor extends Interceptor {
  _GuardInterceptor(this.feature, this.policy, this.log, this.purpose);

  final NetworkFeature feature;
  final NetworkPolicy policy;
  final NetworkLog log;
  final String? purpose;

  static const _logIdKey = 'networkGuard.logId';
  static const _stopwatchKey = 'networkGuard.stopwatch';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final blocked = _checkPolicy(feature, policy, options.uri);
    if (blocked != null) {
      await log.record(
        feature: feature,
        method: options.method,
        host: options.uri.host,
        path: options.uri.path,
        purpose: purpose,
        outcome: _outcomeFor(blocked),
      );
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: NetworkBlockedByPolicyException(
            feature: feature,
            reason: blocked,
          ),
        ),
      );
      return;
    }

    options.extra[_stopwatchKey] = Stopwatch()..start();
    options.extra[_logIdKey] = await log.open(
      feature: feature,
      method: options.method,
      host: options.uri.host,
      path: options.uri.path,
      purpose: purpose,
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    await _close(
      response.requestOptions,
      outcome: NetworkOutcome.allowed,
      statusCode: response.statusCode,
      bytesReceived: _contentLength(response.headers.value(Headers.contentLengthHeader)),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // A block is already logged by record() in onRequest — closing a row
    // that was never opened would just overwrite an unrelated one.
    if (err.error is! NetworkBlockedByPolicyException) {
      await _close(
        err.requestOptions,
        outcome: err.type == DioExceptionType.cancel
            ? NetworkOutcome.cancelled
            : NetworkOutcome.failed,
        statusCode: err.response?.statusCode,
      );
    }
    handler.next(err);
  }

  Future<void> _close(
    RequestOptions options, {
    required NetworkOutcome outcome,
    int? statusCode,
    int? bytesReceived,
  }) async {
    final id = options.extra[_logIdKey] as int?;
    if (id == null) return;
    final stopwatch = options.extra[_stopwatchKey] as Stopwatch?;
    await log.close(
      id,
      outcome: outcome,
      statusCode: statusCode,
      duration: stopwatch?.elapsed,
      bytesReceived: bytesReceived,
    );
  }

  int? _contentLength(String? headerValue) =>
      headerValue == null ? null : int.tryParse(headerValue);
}

/// [http.Client] path for callers that need one rather than a [Dio] — today,
/// `flutter_whisper`'s model downloader.
class GuardedHttpClient extends http.BaseClient {
  GuardedHttpClient({
    required this.feature,
    required this.policy,
    required this.log,
    this.purpose,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  final NetworkFeature feature;
  final NetworkPolicy policy;
  final NetworkLog log;
  final String? purpose;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final blocked = _checkPolicy(feature, policy, request.url);
    if (blocked != null) {
      await log.record(
        feature: feature,
        method: request.method,
        host: request.url.host,
        path: request.url.path,
        purpose: purpose,
        outcome: _outcomeFor(blocked),
      );
      throw NetworkBlockedByPolicyException(feature: feature, reason: blocked);
    }

    final logId = await log.open(
      feature: feature,
      method: request.method,
      host: request.url.host,
      path: request.url.path,
      purpose: purpose,
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      await log.close(
        logId,
        outcome: NetworkOutcome.allowed,
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
        bytesReceived: response.contentLength,
      );
      return response;
    } catch (_) {
      await log.close(
        logId,
        outcome: NetworkOutcome.failed,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
