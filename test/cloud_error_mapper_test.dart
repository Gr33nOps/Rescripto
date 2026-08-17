import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/cloud/cloud_error_mapper.dart';
import 'package:rescripto/engine/cloud/openai_compatible_protocol.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/network/network_exceptions.dart';
import 'package:rescripto/services/network/network_feature.dart';

const _protocol = OpenAiCompatibleProtocol();
const _mapper = CloudErrorMapper();

ProviderConfig _provider() {
  final now = DateTime.utc(2026);
  return ProviderConfig(
    id: 'openai-1',
    presetId: 'openai',
    displayName: 'OpenAI',
    credential: const CredentialRef(providerId: 'openai-1', kind: CredentialKind.apiKey),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final provider = _provider();

  group('CloudErrorMapper.map — the policy-block-vs-cancel trap', () {
    // This is the single most important assertion in the phase: a
    // cloudRewrite request blocked by NetworkPolicy must surface
    // CloudAccessBlockedException, never GenerationCancelledException.
    // RewriteController.rewrite() catches GenerationCancelledException and
    // turns it into an empty result with no error set — so getting this
    // wrong would make "your text was blocked from leaving the device"
    // render as a silent no-op.

    test('a policy block wrapped in a DioException (dioFor shape) maps to CloudAccessBlockedException, not cancel', () {
      final blocked = const NetworkBlockedByPolicyException(
        feature: NetworkFeature.cloudRewrite,
        reason: NetworkBlockReason.featureDisabled,
      );
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        type: DioExceptionType.cancel,
        error: blocked,
      );

      final result = _mapper.map(dioError, provider: provider, protocol: _protocol);

      expect(result, isA<CloudAccessBlockedException>());
      expect(
        (result as CloudAccessBlockedException).reason,
        CloudBlockReason.featureDisabled,
      );
      expect(result, isNot(isA<GenerationCancelledException>()));
    });

    test('a policy block thrown bare (httpClientFor shape) also maps correctly', () {
      const blocked = NetworkBlockedByPolicyException(
        feature: NetworkFeature.cloudRewrite,
        reason: NetworkBlockReason.killSwitch,
      );

      final result = _mapper.map(blocked, provider: provider, protocol: _protocol);

      expect(result, isA<CloudAccessBlockedException>());
      expect((result as CloudAccessBlockedException).reason, CloudBlockReason.killSwitch);
    });

    test('secretInUrl block reason is preserved through the mapping', () {
      const blocked = NetworkBlockedByPolicyException(
        feature: NetworkFeature.cloudRewrite,
        reason: NetworkBlockReason.secretInUrl,
      );
      final result = _mapper.map(blocked, provider: provider, protocol: _protocol);
      expect((result as CloudAccessBlockedException).reason, CloudBlockReason.secretInUrl);
    });

    test('a genuine user cancellation (no policy block attached) still maps to GenerationCancelledException', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        type: DioExceptionType.cancel,
      );
      final result = _mapper.map(dioError, provider: provider, protocol: _protocol);
      expect(result, isA<GenerationCancelledException>());
    });
  });

  group('CloudErrorMapper.mapStatusCode — universal HTTP semantics', () {
    test('401 and 403 map to ProviderAuthException carrying the provider id', () {
      for (final status in [401, 403]) {
        final result = _mapper.mapStatusCode(status, null, provider: provider, protocol: _protocol);
        expect(result, isA<ProviderAuthException>());
        expect((result as ProviderAuthException).providerId, 'openai-1');
      }
    });

    test('402 maps to QuotaExhaustedException', () {
      final result = _mapper.mapStatusCode(402, null, provider: provider, protocol: _protocol);
      expect(result, isA<QuotaExhaustedException>());
    });

    test('429 maps to RateLimitedException and parses Retry-After', () {
      final headers = Headers();
      headers.set('retry-after', '30');
      final result = _mapper.mapStatusCode(429, null, provider: provider, protocol: _protocol, headers: headers);
      expect(result, isA<RateLimitedException>());
      expect((result as RateLimitedException).retryAfter, const Duration(seconds: 30));
    });

    test('429 with no Retry-After header still maps, with a null duration', () {
      final result = _mapper.mapStatusCode(429, null, provider: provider, protocol: _protocol);
      expect((result as RateLimitedException).retryAfter, isNull);
    });

    test(
      '429 with a quota-shaped body maps to QuotaExhaustedException, not RateLimitedException',
      () {
        // Regression coverage: verified live against OpenAI — a "no
        // credits remaining" response is HTTP 429 with this exact body
        // shape, indistinguishable from a genuine rate limit by status
        // code alone. Retrying a zero-balance account never succeeds, so
        // showing "try again shortly" here is actively misleading.
        final result = _mapper.mapStatusCode(
          429,
          {
            'error': {
              'message': 'You have no credits remaining.',
              'type': 'insufficient_quota',
              'code': 'credit_balance_exhausted',
            },
          },
          provider: provider,
          protocol: _protocol,
        );
        expect(result, isA<QuotaExhaustedException>());
      },
    );

    test('429 with an unrecognized body still falls back to RateLimitedException', () {
      final result = _mapper.mapStatusCode(
        429,
        {
          'error': {'type': 'rate_limit_exceeded', 'code': 'rate_limit_exceeded'},
        },
        provider: provider,
        protocol: _protocol,
      );
      expect(result, isA<RateLimitedException>());
    });

    test('5xx maps to ProviderUnavailableException carrying the status code', () {
      final result = _mapper.mapStatusCode(503, null, provider: provider, protocol: _protocol);
      expect(result, isA<ProviderUnavailableException>());
      expect((result as ProviderUnavailableException).statusCode, 503);
    });

    test('529 (Anthropic overloaded) also counts as a 5xx provider outage', () {
      final result = _mapper.mapStatusCode(529, null, provider: provider, protocol: _protocol);
      expect(result, isA<ProviderUnavailableException>());
    });

    test('400 delegates to the protocol for body-shape classification', () {
      final result = _mapper.mapStatusCode(
        400,
        {'error': {'code': 'context_length_exceeded'}},
        provider: provider,
        protocol: _protocol,
      );
      expect(result, isA<ContextOverflowException>());
    });
  });

  group('DioExceptionType transport failures', () {
    test('a timeout maps to NetworkUnavailableException', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        _mapper.map(dioError, provider: provider, protocol: _protocol),
        isA<NetworkUnavailableException>(),
      );
    });

    test('a connection error maps to NetworkUnavailableException', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        type: DioExceptionType.connectionError,
      );
      expect(
        _mapper.map(dioError, provider: provider, protocol: _protocol),
        isA<NetworkUnavailableException>(),
      );
    });
  });

  group('security constraint: nativeReason never carries a raw response body', () {
    test('an unknown DioExceptionType never surfaces error/message content', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        error: 'org_id=org-123 sk-live-abcdefghi leaked-looking-text',
      );
      final result = _mapper.map(dioError, provider: provider, protocol: _protocol);
      expect(result, isA<UnknownEngineException>());
      expect(
        (result as UnknownEngineException).nativeReason,
        isNot(contains('sk-live')),
      );
    });
  });
}
