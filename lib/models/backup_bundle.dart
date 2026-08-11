import '../services/credentials/credential_ref.dart';
import 'audience_tag.dart';
import 'history_entry.dart';
import 'provider_config.dart';
import 'tone_preset.dart';
import 'workflow_definition.dart';
import 'workflow_step.dart';

/// The subset of [SettingsService]'s preferences worth carrying across a
/// device — everything with no natural home in another section below.
///
/// A hand-written field list on purpose, not a generic dump of every
/// SharedPreferences key: [BackupService.gather] is what enforces the
/// export allowlist structurally (see that class's own doc), and this is
/// the type that allowlist writes into. `onboardingCompleted` and
/// `cloudFallbackConsent` are deliberately excluded — restoring either onto
/// a different device would silently skip a disclosure the receiving
/// install hasn't actually seen.
class BackupSettings {
  const BackupSettings({
    required this.themeMode,
    required this.threads,
    required this.useGpu,
    required this.contextSize,
    required this.whisperModel,
    required this.processingMode,
    required this.uiMode,
    this.cloudProviderId,
    this.cloudModelRef,
    required this.speechEngine,
  });

  final String themeMode;
  final int threads;
  final bool useGpu;
  final int contextSize;
  final String whisperModel;
  final String processingMode;
  final String uiMode;
  final String? cloudProviderId;
  final String? cloudModelRef;
  final String speechEngine;

  Map<String, Object?> toJson() => {
    'theme_mode': themeMode,
    'threads': threads,
    'use_gpu': useGpu,
    'context_size': contextSize,
    'whisper_model': whisperModel,
    'processing_mode': processingMode,
    'ui_mode': uiMode,
    'cloud_provider_id': cloudProviderId,
    'cloud_model_ref': cloudModelRef,
    'speech_engine': speechEngine,
  };

  factory BackupSettings.fromJson(Map<String, Object?> json) => BackupSettings(
    themeMode: json['theme_mode'] as String? ?? 'system',
    threads: json['threads'] as int? ?? 4,
    useGpu: json['use_gpu'] as bool? ?? false,
    contextSize: json['context_size'] as int? ?? 2048,
    whisperModel: json['whisper_model'] as String? ?? 'base',
    processingMode: json['processing_mode'] as String? ?? 'local',
    uiMode: json['ui_mode'] as String? ?? 'simple',
    cloudProviderId: json['cloud_provider_id'] as String?,
    cloudModelRef: json['cloud_model_ref'] as String?,
    speechEngine: json['speech_engine'] as String? ?? 'local',
  );
}

/// One decrypted secret paired with the [CredentialRef] it belongs to —
/// only ever populated when the caller opts in, and only ever present
/// inside a bundle already behind [BackupBundle.containsSecrets].
class BackupCredential {
  const BackupCredential({required this.ref, required this.secret});

  final CredentialRef ref;
  final String secret;

  Map<String, Object?> toJson() => {
    'provider_id': ref.providerId,
    'account_id': ref.accountId,
    'kind': ref.kind.name,
    'secret': secret,
  };

  factory BackupCredential.fromJson(Map<String, Object?> json) => BackupCredential(
    ref: CredentialRef(
      providerId: json['provider_id'] as String,
      accountId: json['account_id'] as String,
      kind: CredentialKind.values.byName(json['kind'] as String),
    ),
    secret: json['secret'] as String,
  );
}

/// Everything an export/sync round-trip can carry, plus the header that
/// [BackupService.preview] reads without applying anything.
///
/// [containsSecrets] is true only when [credentials] is non-empty — restore
/// screens key their loudest warning off this single field rather than
/// re-deriving it, so there is exactly one place that can get it wrong.
///
/// Model files are never a section here: they are gigabytes and
/// re-downloadable, so only [BackupSettings.selectedModelId]-shaped
/// references would belong, and this app doesn't even export that — the
/// receiving device re-resolves its own default rather than being told to
/// fetch a specific multi-hundred-MB file sight unseen.
class BackupBundle {
  const BackupBundle({
    required this.formatVersion,
    required this.createdAt,
    required this.appVersion,
    required this.dbVersion,
    this.settings,
    this.tones = const [],
    this.audiences = const [],
    this.workflows = const [],
    this.providerConfigs = const [],
    this.history = const [],
    this.credentials = const [],
  });

  /// Bumped whenever this class's own JSON shape changes — independent of
  /// [dbVersion], which tracks the SQLite schema the sections were read
  /// from. [BackupService.restore] refuses a [formatVersion] newer than it
  /// understands rather than guessing at fields it's never seen.
  static const int currentFormatVersion = 1;

  final int formatVersion;
  final DateTime createdAt;
  final String appVersion;
  final int dbVersion;

  final BackupSettings? settings;
  final List<TonePreset> tones;
  final List<AudienceTag> audiences;
  final List<WorkflowDefinition> workflows;
  final List<ProviderConfig> providerConfigs;
  final List<HistoryEntry> history;
  final List<BackupCredential> credentials;

  bool get containsSecrets => credentials.isNotEmpty;

  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'created_at': createdAt.toIso8601String(),
    'app_version': appVersion,
    'db_version': dbVersion,
    'contains_secrets': containsSecrets,
    if (settings != null) 'settings': settings!.toJson(),
    'tones': tones.map((t) => t.toMap()).toList(),
    'audiences': audiences.map((a) => a.toMap()).toList(),
    'workflows': workflows.map(_workflowToJson).toList(),
    'provider_configs': providerConfigs.map(_providerConfigToJson).toList(),
    'history': history.map((h) => h.toMap(includeId: false)).toList(),
    'credentials': credentials.map((c) => c.toJson()).toList(),
  };

  factory BackupBundle.fromJson(Map<String, Object?> json) {
    final settingsJson = json['settings'] as Map<Object?, Object?>?;
    return BackupBundle(
      formatVersion: json['format_version'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      appVersion: json['app_version'] as String,
      dbVersion: json['db_version'] as int,
      settings: settingsJson == null
          ? null
          : BackupSettings.fromJson(Map<String, Object?>.from(settingsJson)),
      tones: _list(json['tones'], (m) => TonePreset.fromMap(m)),
      audiences: _list(json['audiences'], (m) => AudienceTag.fromMap(m)),
      workflows: _list(json['workflows'], _workflowFromJson),
      providerConfigs: _list(json['provider_configs'], _providerConfigFromJson),
      history: _list(json['history'], (m) => HistoryEntry.fromMap({...m, 'id': 0})),
      credentials: _list(json['credentials'], BackupCredential.fromJson),
    );
  }

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, Object?>) parse,
  ) {
    if (raw is! List) return const [];
    return raw
        .map((e) => parse(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  static Map<String, Object?> _workflowToJson(WorkflowDefinition workflow) => {
    'id': workflow.id,
    'name': workflow.name,
    'created_at': workflow.createdAt.toIso8601String(),
    'updated_at': workflow.updatedAt.toIso8601String(),
    'steps': workflow.steps.map((s) => s.toMap()).toList(),
  };

  static WorkflowDefinition _workflowFromJson(Map<String, Object?> json) => WorkflowDefinition(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    steps: _list(json['steps'], WorkflowStep.fromMap),
  );

  /// [ProviderConfig.toMap] never carries a secret — only a [CredentialRef]
  /// — so this section is safe to include even when [containsSecrets] is
  /// false; the credential it points to is what stays gated behind opt-in.
  /// `models` rides alongside because it isn't part of [ProviderConfig.toMap]
  /// (that method mirrors the `provider_config` table exactly, and models
  /// live in a separate table joined in by `ProviderStore`).
  static Map<String, Object?> _providerConfigToJson(ProviderConfig config) => {
    ...config.toMap(),
    'models': config.models.map((m) => m.toMap()).toList(),
  };

  static ProviderConfig _providerConfigFromJson(Map<String, Object?> json) => ProviderConfig.fromMap(
    json,
    models: _list(json['models'], ProviderModelEntry.fromMap),
  );
}
