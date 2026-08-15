import 'dart:convert';

import '../engine/engine_target.dart';
import '../services/credentials/credential_ref.dart';
import 'provider_preset.dart';

/// One model name a user has added to a [ProviderConfig] beyond its preset's
/// [ProviderPreset.knownModels] — the escape hatch for Ollama's locally
/// pulled models, a custom endpoint's own catalog, or any provider model
/// released after this app's `knownModels` list was written.
class ProviderModelEntry {
  const ProviderModelEntry({required this.modelRef, required this.displayName});

  final String modelRef;
  final String displayName;

  Map<String, Object?> toMap() => {
    'model_ref': modelRef,
    'display_name': displayName,
  };

  factory ProviderModelEntry.fromMap(Map<String, Object?> row) =>
      ProviderModelEntry(
        modelRef: row['model_ref'] as String,
        displayName: row['display_name'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ProviderModelEntry &&
      other.modelRef == modelRef &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(modelRef, displayName);
}

/// A user-configured instance of a [ProviderPreset] — the row that gets
/// persisted, backed up, and pointed at from an [EngineTarget].
///
/// Holds a [CredentialRef], never a secret string: this is the type that
/// ends up in SQLite and in an export bundle, so the persistence layer has
/// no type capable of carrying a key. [CredentialRef.providerId] is set to
/// this config's own [id] rather than to [presetId] — a user may configure
/// the same preset more than once (two OpenAI accounts, two Ollama boxes),
/// and each configured instance owns exactly one credential slot.
class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.presetId,
    required this.displayName,
    required this.credential,
    this.baseUrlOverride,
    this.enabled = true,
    this.extraHeaders = const {},
    this.models = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique per configured instance — not the same as [presetId].
  final String id;

  /// Which [ProviderPreset] this instance is configured over.
  final String presetId;

  /// User-facing name, e.g. "OpenAI (work)".
  final String displayName;

  final CredentialRef credential;

  /// Overrides [ProviderPreset.baseUrl]. Required (non-null, non-empty) for
  /// a preset with [ProviderPreset.editableBaseUrl] true.
  final String? baseUrlOverride;

  final bool enabled;

  /// Extra static headers on top of [ProviderPreset.extraHeaders] — never
  /// validated to contain a credential; see [validateExtraHeaders].
  final Map<String, String> extraHeaders;

  /// Models the user has added beyond [ProviderPreset.knownModels].
  final List<ProviderModelEntry> models;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The preset this config is layered over. Throws if [presetId] no longer
  /// names a known preset — a config referencing a removed preset is a data
  /// problem the caller needs to see, not silently paper over.
  ProviderPreset get preset {
    final found = ProviderPresetCatalog.byId(presetId);
    if (found == null) {
      throw StateError(
        'ProviderConfig "$id" references unknown preset "$presetId".',
      );
    }
    return found;
  }

  /// Every selectable model: the preset's built-ins, then anything the user
  /// added. Deliberately not de-duplicated beyond simple identity — a user
  /// re-adding a known model just shows it twice in the built-in slot, which
  /// is harmless and simpler than a merge policy nobody asked for.
  List<ProviderModelEntry> get allModels => [
    for (final name in preset.knownModels)
      ProviderModelEntry(modelRef: name, displayName: name),
    ...models,
  ];

  Uri get baseUrl =>
      normalizeBaseUrl(baseUrlOverride ?? preset.baseUrl, preset);

  EngineTarget targetFor(String modelRef) => EngineTarget(
    engineId: preset.protocol.engineId,
    modelRef: modelRef,
    providerId: id,
  );

  static const _forbiddenHeaderKeys = {
    'authorization',
    'x-api-key',
    'x-goog-api-key',
    'proxy-authorization',
    'cookie',
  };

  /// Rejects any header that could carry a credential. `extraHeaders` exists
  /// for identification headers like OpenRouter's `HTTP-Referer` — never for
  /// auth, which is [CredentialStore]'s job alone.
  static void validateExtraHeaders(Map<String, String> headers) {
    for (final key in headers.keys) {
      if (_forbiddenHeaderKeys.contains(key.toLowerCase())) {
        throw ArgumentError(
          'extraHeaders may not set "$key" because that header carries a '
          'credential and must come from CredentialStore instead.',
        );
      }
    }
  }

  /// Parses [raw] and enforces [preset]'s scheme policy. Refuses `http://`
  /// unless [ProviderPreset.allowsPlainHttp] is true — every hosted provider
  /// must be reached over TLS; only a self-hosted preset may opt out.
  static Uri normalizeBaseUrl(String raw, ProviderPreset preset) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('"$raw" is not a valid base URL.');
    }
    final schemeOk =
        uri.scheme == 'https' ||
        (uri.scheme == 'http' && preset.allowsPlainHttp);
    if (!schemeOk) {
      throw ArgumentError(
        preset.allowsPlainHttp
            ? '"$raw" must use http:// or https://.'
            : '"$raw" must use https://.',
      );
    }
    return uri;
  }

  ProviderConfig copyWith({
    String? displayName,
    CredentialRef? credential,
    String? baseUrlOverride,
    bool? clearBaseUrlOverride,
    bool? enabled,
    Map<String, String>? extraHeaders,
    List<ProviderModelEntry>? models,
    DateTime? updatedAt,
  }) {
    return ProviderConfig(
      id: id,
      presetId: presetId,
      displayName: displayName ?? this.displayName,
      credential: credential ?? this.credential,
      baseUrlOverride: clearBaseUrlOverride == true
          ? null
          : (baseUrlOverride ?? this.baseUrlOverride),
      enabled: enabled ?? this.enabled,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      models: models ?? this.models,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'preset_id': presetId,
    'display_name': displayName,
    'base_url_override': baseUrlOverride,
    'enabled': enabled ? 1 : 0,
    'credential_provider_id': credential.providerId,
    'credential_account_id': credential.accountId,
    'credential_kind': credential.kind.name,
    'extra_headers': jsonEncode(extraHeaders),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ProviderConfig.fromMap(
    Map<String, Object?> row, {
    List<ProviderModelEntry> models = const [],
  }) {
    return ProviderConfig(
      id: row['id'] as String,
      presetId: row['preset_id'] as String,
      displayName: row['display_name'] as String,
      credential: CredentialRef(
        providerId: row['credential_provider_id'] as String,
        accountId: row['credential_account_id'] as String,
        kind: CredentialKind.values.byName(row['credential_kind'] as String),
      ),
      baseUrlOverride: row['base_url_override'] as String?,
      enabled: (row['enabled'] as int) != 0,
      extraHeaders: Map<String, String>.from(
        jsonDecode(row['extra_headers'] as String) as Map,
      ),
      models: models,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  // Never the default toString — the commonest real leak is an interpolated
  // exception message, and this type is the one that's always near a
  // CredentialRef (even though the ref itself is safe to print too).
  @override
  String toString() => 'ProviderConfig($id, preset: $presetId, "$displayName")';
}
