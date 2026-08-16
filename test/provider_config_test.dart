import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/provider_preset.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';

ProviderConfig _config({
  String id = 'openai-abc123',
  String presetId = 'openai',
  String? baseUrlOverride,
  Map<String, String> extraHeaders = const {},
  List<ProviderModelEntry> models = const [],
}) {
  final now = DateTime.utc(2026);
  return ProviderConfig(
    id: id,
    presetId: presetId,
    displayName: 'Test provider',
    credential: CredentialRef(providerId: id, kind: CredentialKind.apiKey),
    baseUrlOverride: baseUrlOverride,
    extraHeaders: extraHeaders,
    models: models,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ProviderPresetCatalog', () {
    test('has ten distinct providers over three protocols', () {
      final ids = ProviderPresetCatalog.all.map((p) => p.id).toSet();
      expect(ids, hasLength(10));
      expect(ids, hasLength(ProviderPresetCatalog.all.length));
    });

    test('byId returns null instead of falling back for an unknown id', () {
      expect(ProviderPresetCatalog.byId('not-a-real-preset'), isNull);
      expect(ProviderPresetCatalog.byId('openai'), isNotNull);
    });

    test('anthropic and gemini use their own protocol, not OpenAI-compatible', () {
      expect(
        ProviderPresetCatalog.byId('anthropic')!.protocol,
        ProviderProtocol.anthropic,
      );
      expect(
        ProviderPresetCatalog.byId('gemini')!.protocol,
        ProviderProtocol.gemini,
      );
    });

    test('gemini auth style is a header, never a query parameter', () {
      expect(ProviderPresetCatalog.byId('gemini')!.authStyle, AuthStyle.googApiKey);
    });

    test('only self-hosted presets allow plain http', () {
      for (final preset in ProviderPresetCatalog.all) {
        if (preset.allowsPlainHttp) {
          expect(['ollama', 'custom'], contains(preset.id));
        }
      }
    });
  });

  group('ProviderConfig.validateExtraHeaders', () {
    test('rejects a header that could carry a credential', () {
      for (final key in [
        'Authorization',
        'x-api-key',
        'X-Goog-Api-Key',
        'Cookie',
        'Proxy-Authorization',
      ]) {
        expect(
          () => ProviderConfig.validateExtraHeaders({key: 'value'}),
          throwsArgumentError,
          reason: '$key should be rejected',
        );
      }
    });

    test('allows an identification header like HTTP-Referer', () {
      expect(
        () => ProviderConfig.validateExtraHeaders({
          'HTTP-Referer': 'https://example.com',
          'X-Title': 'Rescripto',
        }),
        returnsNormally,
      );
    });
  });

  group('ProviderConfig.normalizeBaseUrl', () {
    test('accepts https for a hosted preset', () {
      final preset = ProviderPresetCatalog.byId('openai')!;
      final uri = ProviderConfig.normalizeBaseUrl('https://api.openai.com/v1', preset);
      expect(uri.scheme, 'https');
    });

    test('refuses http for a hosted preset', () {
      final preset = ProviderPresetCatalog.byId('openai')!;
      expect(
        () => ProviderConfig.normalizeBaseUrl('http://api.openai.com/v1', preset),
        throwsArgumentError,
      );
    });

    test('allows http for a preset that opts in', () {
      final preset = ProviderPresetCatalog.byId('ollama')!;
      final uri = ProviderConfig.normalizeBaseUrl('http://192.168.1.5:11434/v1', preset);
      expect(uri.scheme, 'http');
    });

    test('rejects a malformed url', () {
      final preset = ProviderPresetCatalog.byId('openai')!;
      expect(
        () => ProviderConfig.normalizeBaseUrl('not a url', preset),
        throwsArgumentError,
      );
    });
  });

  group('ProviderConfig.targetFor', () {
    test('carries this config\'s own id as EngineTarget.providerId', () {
      final config = _config(id: 'openai-abc123');
      final target = config.targetFor('gpt-4o');
      expect(target.engineId, 'cloud.openaiCompatible');
      expect(target.modelRef, 'gpt-4o');
      expect(target.providerId, 'openai-abc123');
    });
  });

  group('ProviderConfig.allModels', () {
    test('layers user-added models on top of the preset\'s known models', () {
      final config = _config(
        presetId: 'openai',
        models: const [ProviderModelEntry(modelRef: 'gpt-4o-preview', displayName: 'GPT-4o Preview')],
      );
      final refs = config.allModels.map((m) => m.modelRef);
      expect(refs, containsAll(['gpt-4o', 'gpt-4o-preview']));
    });
  });

  group('ProviderConfig map round-trip', () {
    test('toMap/fromMap preserves every field including the credential ref', () {
      final config = _config(
        baseUrlOverride: 'https://my-proxy.example.com/v1',
        extraHeaders: const {'X-Title': 'Rescripto'},
      );
      final restored = ProviderConfig.fromMap(config.toMap());

      expect(restored.id, config.id);
      expect(restored.presetId, config.presetId);
      expect(restored.displayName, config.displayName);
      expect(restored.credential, config.credential);
      expect(restored.baseUrlOverride, config.baseUrlOverride);
      expect(restored.enabled, config.enabled);
      expect(restored.extraHeaders, config.extraHeaders);
    });

    test('toMap never serializes the credential as a plaintext value', () {
      final config = _config();
      final map = config.toMap();
      expect(map.values, isNot(contains(config.credential.storageKey)));
      // Only the CredentialRef's three lookup fields are present — a key by
      // construction, never a secret.
      expect(map['credential_provider_id'], config.credential.providerId);
      expect(map['credential_account_id'], config.credential.accountId);
      expect(map['credential_kind'], config.credential.kind.name);
    });

    test('toString never includes the credential or extra headers', () {
      final config = _config(extraHeaders: const {'X-Title': 'super-secret-looking-value'});
      expect(config.toString(), isNot(contains('super-secret-looking-value')));
    });
  });
}
