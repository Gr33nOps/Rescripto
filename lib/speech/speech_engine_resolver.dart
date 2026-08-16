import '../models/provider_config.dart';
import '../models/provider_preset.dart';
import '../services/credentials/credential_store.dart';
import '../services/network/network_guard.dart';
import '../services/providers/provider_registry.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import 'cloud_speech_engine.dart';
import 'local_whisper_speech_engine.dart';
import 'speech_engine.dart';

/// Raised when `speechEngine` names cloud but nothing can serve it.
///
/// Deliberately not a silent fall back to local. Falling back would be the
/// *safe* direction for privacy — but it would also mean the setting quietly
/// does nothing, which is the exact failure this resolver exists to end:
/// `speechEngine` was a stored preference that no code ever read, so picking
/// "Cloud" changed a value in SharedPreferences and nothing else.
class SpeechEngineUnavailable implements Exception {
  const SpeechEngineUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Picks the [SpeechEngine] for the current `speechEngine` setting.
///
/// Only two are offered. `SystemSpeechEngine` exists and declares the right
/// capabilities, but every one of its methods throws — it needs a platform
/// channel to Android's `SpeechRecognizer` that isn't built — so offering it
/// would be offering a guaranteed crash. It stays out of both this resolver
/// and the settings UI until it actually works.
class SpeechEngineResolver {
  const SpeechEngineResolver({
    required this.settings,
    required this.speechService,
    required this.providerRegistry,
    required this.credentialStore,
    required this.networkGuard,
  });

  final SettingsService settings;
  final SpeechService speechService;
  final ProviderRegistry providerRegistry;
  final CredentialStore credentialStore;
  final NetworkGuard networkGuard;

  static const String localId = 'local';
  static const String cloudId = 'cloud';

  /// Whether a cloud transcription provider is actually set up — what the
  /// settings screen greys the Cloud option out on, so the choice is never
  /// offered as available and then refused at record time.
  bool get hasCloudSpeechProvider => _speechCapableProvider != null;

  /// Name shown in Settings so users can tell which service transcribes
  /// their recording before the selected cloud text model receives it.
  String? get cloudSpeechProviderName => _speechCapableProvider?.displayName;

  /// The first enabled provider whose preset advertises transcription.
  ///
  /// [ProviderPreset.supportsSpeech] is only meaningful for OpenAI-compatible
  /// presets — Anthropic and Gemini have no equivalent endpoint — and
  /// `CloudSpeechEngine` posts to an OpenAI-shaped `audio/transcriptions`
  /// path, so the protocol is checked here too rather than trusting the flag
  /// alone.
  ProviderConfig? get _speechCapableProvider {
    for (final config in providerRegistry.enabledConfigs) {
      final preset = ProviderPresetCatalog.byId(config.presetId);
      if (preset == null) continue;
      final xaiEndpoint = config.baseUrl.host == 'api.x.ai';
      if ((preset.supportsSpeech || xaiEndpoint) &&
          preset.protocol == ProviderProtocol.openAiCompatible) {
        return config;
      }
    }
    return null;
  }

  SpeechEngine resolve() {
    if (settings.speechEngine != cloudId) return _local();

    final provider = _speechCapableProvider;
    if (provider == null) {
      throw const SpeechEngineUnavailable(
        'Cloud voice input needs a provider that supports transcription '
        '(OpenAI, Groq, or xAI/Grok), enabled in Cloud providers. Add one, or '
        'switch '
        'voice input back to On-device in Settings.',
      );
    }
    return CloudSpeechEngine(provider, credentialStore, networkGuard);
  }

  SpeechEngine _local() =>
      LocalWhisperSpeechEngine(speechService, settings, networkGuard);
}
