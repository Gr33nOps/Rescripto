import 'package:dio/dio.dart';

import '../../models/provider_config.dart';
import '../../services/network/network_exceptions.dart';
import '../engine_exception.dart';
import 'chat_protocol.dart';

/// Turns whatever a cloud request threw into a typed [EngineException].
///
/// **The highest-risk piece of this whole phase.** `NetworkGuard.dioFor`
/// rejects a policy-blocked request as
/// `DioException(type: DioExceptionType.cancel, error: NetworkBlockedByPolicyException(...))`.
/// A mapper that checks `DioExceptionType.cancel` first — the natural way to
/// write this — would return `GenerationCancelledException`, which
/// `RewriteController` already catches and turns into an *empty result with
/// no error set*. Net effect: "your text was blocked from leaving the
/// device" would render as a silent no-op, on the exact property Phase 1
/// was built to guarantee. So [map] unwraps a policy block *before* looking
/// at `DioExceptionType` at all, and handles both throw shapes —
/// `NetworkGuard.dioFor` wraps it in a `DioException`, `httpClientFor`
/// throws it bare.
class CloudErrorMapper {
  const CloudErrorMapper();

  EngineException map(
    Object error, {
    required ProviderConfig provider,
    required ChatProtocol protocol,
  }) {
    final blocked = _asPolicyBlock(error);
    if (blocked != null) {
      return CloudAccessBlockedException(_toCloudBlockReason(blocked.reason));
    }

    if (error is DioException) {
      return _mapDioException(error, provider, protocol);
    }

    return const UnknownEngineException();
  }

  NetworkBlockedByPolicyException? _asPolicyBlock(Object error) {
    if (error is NetworkBlockedByPolicyException) return error;
    if (error is DioException && error.error is NetworkBlockedByPolicyException) {
      return error.error as NetworkBlockedByPolicyException;
    }
    return null;
  }

  CloudBlockReason _toCloudBlockReason(NetworkBlockReason reason) => switch (reason) {
    NetworkBlockReason.killSwitch => CloudBlockReason.killSwitch,
    NetworkBlockReason.featureDisabled => CloudBlockReason.featureDisabled,
    NetworkBlockReason.secretInUrl => CloudBlockReason.secretInUrl,
  };

  EngineException _mapDioException(
    DioException error,
    ProviderConfig provider,
    ChatProtocol protocol,
  ) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
        return const NetworkUnavailableException();
      case DioExceptionType.cancel:
        return const GenerationCancelledException();
      case DioExceptionType.badResponse:
        return mapStatusCode(
          error.response?.statusCode,
          error.response?.data,
          provider: provider,
          protocol: protocol,
          headers: error.response?.headers,
        );
      case DioExceptionType.unknown:
        return const UnknownEngineException();
    }
  }

  /// The universal HTTP-status table every provider agrees on, extracted as
  /// its own entry point: `CloudRewriteEngine` calls this directly too, for
  /// a non-2xx response it read manually rather than one Dio raised as a
  /// `DioException` — streaming responses go through `validateStatus: (_) =>
  /// true` so a bad status can be classified from the actual decoded body
  /// instead of the raw stream object Dio would otherwise hand back.
  EngineException mapStatusCode(
    int? statusCode,
    Object? body, {
    required ProviderConfig provider,
    required ChatProtocol protocol,
    Headers? headers,
  }) {
    if (statusCode == 429) {
      return RateLimitedException(_retryAfter(headers));
    }
    if (statusCode == 401 || statusCode == 403) {
      return ProviderAuthException(provider.id);
    }
    if (statusCode == 402) {
      return const QuotaExhaustedException();
    }
    if (statusCode != null && statusCode >= 500) {
      return ProviderUnavailableException(statusCode);
    }

    // Everything else (400 and anything unexpected) needs the provider's
    // own error-body shape to classify further.
    return protocol.classifyError(provider, statusCode, body);
  }

  Duration? _retryAfter(Headers? headers) {
    final value = headers?.value('retry-after');
    if (value == null) return null;
    final seconds = int.tryParse(value);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
