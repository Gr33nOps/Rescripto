/// The wire protocol a cloud provider speaks.
///
/// Nine named providers, three protocols: OpenAI, Groq, OpenRouter, Mistral,
/// Together, Ollama and a custom endpoint all speak OpenAI chat-completions;
/// Anthropic and Gemini have their own shapes. [ProviderPreset] expresses
/// every provider as configuration over one of these three, so a tenth
/// OpenAI-compatible provider is a table row, not new code.
enum ProviderProtocol { openAiCompatible, anthropic, gemini }

extension ProviderProtocolEngine on ProviderProtocol {
  /// The [RewriteEngine] id (`lib/engine/`) that handles this protocol. One
  /// engine instance per protocol serves every provider that speaks it —
  /// which provider is picked per-request via `EngineTarget.providerId`.
  String get engineId => switch (this) {
    ProviderProtocol.openAiCompatible => 'cloud.openaiCompatible',
    ProviderProtocol.anthropic => 'cloud.anthropic',
    ProviderProtocol.gemini => 'cloud.gemini',
  };
}

/// How a provider expects its credential presented.
enum AuthStyle {
  /// `Authorization: Bearer <key>` — every OpenAI-compatible provider.
  bearer,

  /// `x-api-key: <key>` (plus `anthropic-version`) — Anthropic.
  xApiKey,

  /// `x-goog-api-key: <key>` — Gemini. Never `?key=`: `NetworkGuard` refuses
  /// a `cloudRewrite` request with a secret in its query string.
  googApiKey,
}

/// A named cloud provider, expressed as configuration over one of three
/// protocol adapters rather than as its own engine.
///
/// Fields that vary per-request-shape live here, not on the protocol
/// implementation — otherwise three protocols become nine. Mistral 400s on
/// `stream_options`; OpenRouter wants identifying headers; Anthropic caps
/// stop sequences and temperature. Each such quirk is a flag below, read by
/// the shared protocol implementation for that provider's [protocol].
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.baseUrl,
    required this.authStyle,
    this.requiresKey = true,
    this.allowsPlainHttp = false,
    this.editableBaseUrl = false,
    this.knownModels = const [],
    this.docsUrl,
    this.extraHeaders = const {},
    this.supportsUsageInStream = true,
    this.usesMaxCompletionTokens = false,
    this.maxStopSequences,
    this.maxTemperature,
    this.supportsSpeech = false,
  });

  /// Stable id, e.g. `'openai'`. Referenced by `ProviderConfig.presetId`.
  final String id;
  final String displayName;
  final ProviderProtocol protocol;

  /// Default API base URL. Empty for presets with no sensible default (a
  /// fully custom endpoint) — [editableBaseUrl] is true whenever a user must
  /// supply or may override this.
  final String baseUrl;

  final AuthStyle authStyle;

  /// False only for a locally-run, unauthenticated endpoint (Ollama's
  /// default install has no auth).
  final bool requiresKey;

  /// Allows `http://` for this preset's base URL — self-hosted endpoints on
  /// a LAN (Ollama, a custom endpoint) only. Every hosted provider requires
  /// `https://`; `ProviderConfig.normalizeBaseUrl` enforces it.
  final bool allowsPlainHttp;

  /// Whether the provider-edit screen should let the user type a base URL
  /// rather than showing [baseUrl] as fixed text.
  final bool editableBaseUrl;

  /// A representative starting model list for the picker — not exhaustive
  /// and not guaranteed current, since provider catalogs change faster than
  /// this app does. `ProviderConfig.allModels` layers any models the user
  /// has added on top of this list; that is the escape hatch, not a bigger
  /// static list here.
  final List<String> knownModels;

  /// Where to go to get a key for this provider, shown in the provider-edit
  /// screen. Never fetched — display only.
  final String? docsUrl;

  /// Static headers sent with every request to this provider (OpenRouter's
  /// `HTTP-Referer`/`X-Title`). Never a place a credential can live —
  /// `ProviderConfig.validateExtraHeaders` enforces that for anything a user
  /// adds on top of this.
  final Map<String, String> extraHeaders;

  /// Whether to request usage totals inline in the SSE stream
  /// (`stream_options.include_usage`). Mistral 400s on this field entirely.
  final bool supportsUsageInStream;

  /// Whether this provider wants `max_completion_tokens` instead of
  /// `max_tokens` — true only for OpenAI's o-series reasoning models. None
  /// of the default [knownModels] below need it; plumbed through for a user
  /// who adds one.
  final bool usesMaxCompletionTokens;

  /// Upper bound on how many stop sequences a request may carry, or null
  /// for "the protocol's own default is fine." Anthropic caps at 4.
  final int? maxStopSequences;

  /// Upper bound on `temperature`, or null for no extra cap beyond the
  /// protocol's own. Anthropic caps at 1.0.
  final double? maxTemperature;

  /// Whether this preset's endpoint also serves an OpenAI-compatible speech
  /// (Whisper) API — see `lib/speech/`. Only meaningful for
  /// [ProviderProtocol.openAiCompatible] presets.
  final bool supportsSpeech;

  @override
  String toString() => 'ProviderPreset($id, $protocol)';
}

/// The built-in catalog: nine named providers over three protocols.
class ProviderPresetCatalog {
  const ProviderPresetCatalog._();

  static const List<ProviderPreset> all = [
    ProviderPreset(
      id: 'openai',
      displayName: 'OpenAI',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      authStyle: AuthStyle.bearer,
      knownModels: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-mini'],
      docsUrl: 'https://platform.openai.com/api-keys',
      supportsSpeech: true,
    ),
    ProviderPreset(
      id: 'anthropic',
      displayName: 'Anthropic',
      protocol: ProviderProtocol.anthropic,
      baseUrl: 'https://api.anthropic.com/v1',
      authStyle: AuthStyle.xApiKey,
      knownModels: [
        'claude-sonnet-4-20250514',
        'claude-opus-4-20250514',
        'claude-3-5-haiku-20241022',
      ],
      docsUrl: 'https://console.anthropic.com/settings/keys',
      maxStopSequences: 4,
      maxTemperature: 1.0,
    ),
    ProviderPreset(
      id: 'gemini',
      displayName: 'Google Gemini',
      protocol: ProviderProtocol.gemini,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      authStyle: AuthStyle.googApiKey,
      knownModels: ['gemini-2.5-pro', 'gemini-2.5-flash'],
      docsUrl: 'https://aistudio.google.com/apikey',
    ),
    ProviderPreset(
      id: 'groq',
      displayName: 'Groq',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://api.groq.com/openai/v1',
      authStyle: AuthStyle.bearer,
      knownModels: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
      docsUrl: 'https://console.groq.com/keys',
      supportsSpeech: true,
    ),
    ProviderPreset(
      id: 'xai',
      displayName: 'xAI (Grok)',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://api.x.ai/v1',
      authStyle: AuthStyle.bearer,
      knownModels: ['grok-4.1-fast-reasoning', 'grok-4.1-mini'],
      docsUrl: 'https://console.x.ai',
      supportsSpeech: true,
    ),
    ProviderPreset(
      id: 'openrouter',
      displayName: 'OpenRouter',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://openrouter.ai/api/v1',
      authStyle: AuthStyle.bearer,
      // OpenRouter asks integrations to identify themselves with these two
      // headers; neither carries a credential.
      extraHeaders: {
        'HTTP-Referer': 'https://github.com/Gr33nOps/Rescripto',
        'X-Title': 'Rescripto',
      },
      docsUrl: 'https://openrouter.ai/keys',
    ),
    ProviderPreset(
      id: 'mistral',
      displayName: 'Mistral',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://api.mistral.ai/v1',
      authStyle: AuthStyle.bearer,
      knownModels: ['mistral-large-latest', 'mistral-small-latest'],
      docsUrl: 'https://console.mistral.ai/api-keys',
      // Mistral's chat-completions endpoint 400s on a `stream_options` body
      // field the other OpenAI-compatible providers accept.
      supportsUsageInStream: false,
    ),
    ProviderPreset(
      id: 'together',
      displayName: 'Together AI',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'https://api.together.xyz/v1',
      authStyle: AuthStyle.bearer,
      knownModels: ['meta-llama/Llama-3.3-70B-Instruct-Turbo'],
      docsUrl: 'https://api.together.ai/settings/api-keys',
    ),
    ProviderPreset(
      id: 'ollama',
      displayName: 'Ollama (local network)',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: 'http://localhost:11434/v1',
      authStyle: AuthStyle.bearer,
      requiresKey: false,
      allowsPlainHttp: true,
      editableBaseUrl: true,
      docsUrl: 'https://github.com/ollama/ollama',
    ),
    ProviderPreset(
      id: 'custom',
      displayName: 'Custom endpoint',
      protocol: ProviderProtocol.openAiCompatible,
      baseUrl: '',
      authStyle: AuthStyle.bearer,
      requiresKey: false,
      allowsPlainHttp: true,
      editableBaseUrl: true,
    ),
  ];

  /// Looks up a preset by id, or null if none matches — no first-of-list
  /// fallback, the same lesson `ModelCatalog.byId` and `ConfigStore.toneById`
  /// already learned.
  static ProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
