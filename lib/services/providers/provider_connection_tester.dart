import 'package:dio/dio.dart';

import '../../engine/cloud/anthropic_protocol.dart';
import '../../engine/cloud/chat_protocol.dart';
import '../../engine/cloud/cloud_error_mapper.dart';
import '../../engine/cloud/gemini_protocol.dart';
import '../../engine/cloud/openai_compatible_protocol.dart';
import '../../engine/engine_exception.dart';
import '../../models/provider_config.dart';
import '../../models/provider_preset.dart';
import '../credentials/credential_store.dart';
import '../network/network_feature.dart';
import '../network/network_guard.dart';

/// Verifies a [ProviderConfig] can actually reach its provider, for the
/// "Test connection" button on the provider-edit screen.
///
/// Reuses each protocol's own [ChatProtocol.authHeader] rather than
/// building its own auth logic, so the credential goes out exactly the way
/// a real rewrite would send it — in particular, Gemini's key goes through
/// `x-goog-api-key`, never `?key=`, and `NetworkGuard` would refuse the
/// latter regardless. Hits each protocol's model-listing endpoint, which
/// every one of the three supports and none of them bill for, rather than
/// spending a real generation just to check a key works.
class ProviderConnectionTester {
  const ProviderConnectionTester(
    this._networkGuard,
    this._credentialStore, {
    this.errorMapper = const CloudErrorMapper(),
  });

  final NetworkGuard _networkGuard;
  final CredentialStore _credentialStore;
  final CloudErrorMapper errorMapper;

  ChatProtocol _protocolFor(ProviderProtocol protocol) => switch (protocol) {
    ProviderProtocol.openAiCompatible => const OpenAiCompatibleProtocol(),
    ProviderProtocol.anthropic => const AnthropicProtocol(),
    ProviderProtocol.gemini => const GeminiProtocol(),
  };

  /// Returns normally on success; throws a typed [EngineException] — the
  /// same vocabulary a real rewrite failure would use — on failure.
  Future<void> test(ProviderConfig provider) async {
    final protocol = _protocolFor(provider.preset.protocol);
    final secret = await _credentialStore.read(provider.credential);
    if (secret == null && provider.preset.requiresKey) {
      throw ProviderNotConfiguredException(provider.id);
    }

    final headers = {...protocol.headers(provider)};
    if (secret != null) {
      final auth = protocol.authHeader(provider, secret);
      headers[auth.key] = auth.value;
    }

    final uri = joinPath(provider.baseUrl, 'models');
    final dio = _networkGuard.dioFor(
      NetworkFeature.cloudRewrite,
      purpose: 'Test connection: ${provider.displayName}',
    );

    try {
      final response = await dio.get<Object?>(
        uri.toString(),
        options: Options(
          headers: headers,
          validateStatus: (_) => true,
          connectTimeout: const Duration(seconds: 15),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) return;
      throw errorMapper.mapStatusCode(
        status,
        response.data,
        provider: provider,
        protocol: protocol,
        headers: response.headers,
      );
    } on EngineException {
      rethrow;
    } catch (e) {
      throw errorMapper.map(e, provider: provider, protocol: protocol);
    }
  }
}
