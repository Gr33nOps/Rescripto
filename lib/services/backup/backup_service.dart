import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../../models/backup_bundle.dart';
import '../../models/processing_mode.dart';
import '../../models/ui_mode.dart';
import '../config_store.dart';
import '../credentials/credential_store.dart';
import '../providers/provider_registry.dart';
import '../settings_service.dart';
import '../storage_service.dart';
import '../workflows/workflow_registry.dart';
import 'backup_crypto.dart';
import 'backup_exception.dart';
import 'restore_options.dart';

/// Gathers app state into a [BackupBundle] and encrypts/decrypts it for
/// export, import, and (Step 4) sync.
///
/// [gather] is the allowlist [BackupBundle]'s own doc promises: every field
/// it reads is named here explicitly, so a future field added to
/// `SettingsService` or a model doesn't silently start riding along in a
/// backup just because it exists — someone has to add a line here on
/// purpose.
class BackupService {
  BackupService({
    required this.settings,
    required this.configStore,
    required this.workflowRegistry,
    required this.providerRegistry,
    required this.storage,
    required this.credentialStore,
    BackupCrypto? crypto,
  }) : crypto = crypto ?? BackupCrypto();

  final SettingsService settings;
  final ConfigStore configStore;
  final WorkflowRegistry workflowRegistry;
  final ProviderRegistry providerRegistry;
  final StorageService storage;
  final CredentialStore credentialStore;
  final BackupCrypto crypto;

  /// Reads current app state into a bundle. Every section defaults to
  /// included **except** [includeHistory] and [includeCredentials] — those
  /// two stay opt-in even for a caller that skips the UI entirely, so the
  /// safer bundle is always the one produced with no arguments. The other
  /// five flags exist for [SyncService]'s per-section selection (Step 5);
  /// a manual export or a scheduled backup never has a reason to pass them.
  Future<BackupBundle> gather({
    bool includeSettings = true,
    bool includeTones = true,
    bool includeAudiences = true,
    bool includeWorkflows = true,
    bool includeProviderConfigs = true,
    bool includeHistory = false,
    bool includeCredentials = false,
  }) async {
    var credentials = const <BackupCredential>[];
    if (includeCredentials) {
      final refs = await credentialStore.listRefs();
      final entries = <BackupCredential>[];
      for (final ref in refs) {
        final secret = await credentialStore.read(ref);
        // A ref the Keystore can't currently produce a value for (device
        // restore invalidated it, etc.) is skipped rather than exported as
        // a configured-but-empty credential — nothing to carry across.
        if (secret != null) entries.add(BackupCredential(ref: ref, secret: secret));
      }
      credentials = entries;
    }

    return BackupBundle(
      formatVersion: BackupBundle.currentFormatVersion,
      createdAt: DateTime.now(),
      appVersion: AppConstants.versionName,
      dbVersion: AppConstants.dbVersion,
      settings: includeSettings
          ? BackupSettings(
              themeMode: settings.themeMode,
              threads: settings.threads,
              useGpu: settings.useGpu,
              contextSize: settings.contextSize,
              whisperModel: settings.whisperModel,
              processingMode: settings.processingMode.name,
              uiMode: settings.uiMode.name,
              cloudProviderId: settings.cloudProviderId,
              cloudModelRef: settings.cloudModelRef,
              speechEngine: settings.speechEngine,
            )
          : null,
      tones: includeTones ? configStore.tones : const [],
      audiences: includeAudiences ? configStore.audiences : const [],
      workflows: includeWorkflows ? workflowRegistry.workflows : const [],
      providerConfigs: includeProviderConfigs ? providerRegistry.configs : const [],
      history: includeHistory ? await storage.getHistory() : const [],
      credentials: credentials,
    );
  }

  /// Serializes and encrypts [bundle] with [passphrase]. The returned bytes
  /// are a complete, self-contained file — everything [decrypt] needs
  /// (salt, nonce, MAC) travels with them.
  Future<Uint8List> export(BackupBundle bundle, String passphrase) async {
    final jsonBytes = utf8.encode(jsonEncode(bundle.toJson()));
    return crypto.encrypt(Uint8List.fromList(jsonBytes), passphrase);
  }

  /// Decrypts [fileBytes] with [passphrase] and parses the result. Throws
  /// [BackupWrongPassphraseException] on a bad passphrase or tampered file,
  /// [BackupCorruptException] on a file too short or not valid JSON once
  /// decrypted, and [BackupNewerFormatException] if the bundle's own
  /// [BackupBundle.formatVersion] is newer than this build understands.
  Future<BackupBundle> decrypt(Uint8List fileBytes, String passphrase) async {
    final jsonBytes = await crypto.decrypt(fileBytes, passphrase);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(jsonBytes));
    } catch (_) {
      throw const BackupCorruptException();
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackupCorruptException();
    }

    final formatVersion = decoded['format_version'];
    if (formatVersion is! int || formatVersion > BackupBundle.currentFormatVersion) {
      throw BackupNewerFormatException(
        formatVersion is int ? formatVersion : -1,
        BackupBundle.currentFormatVersion,
      );
    }

    try {
      return BackupBundle.fromJson(decoded);
    } catch (_) {
      throw const BackupCorruptException();
    }
  }

  /// Summarizes a decrypted [bundle] without applying anything — what
  /// [restore] would do, in counts, so the import screen can show it before
  /// asking for confirmation.
  BackupPreview preview(BackupBundle bundle) => BackupPreview(
    createdAt: bundle.createdAt,
    appVersion: bundle.appVersion,
    dbVersion: bundle.dbVersion,
    containsSecrets: bundle.containsSecrets,
    hasSettings: bundle.settings != null,
    toneCount: bundle.tones.length,
    audienceCount: bundle.audiences.length,
    workflowCount: bundle.workflows.length,
    providerConfigCount: bundle.providerConfigs.length,
    historyCount: bundle.history.length,
    credentialCount: bundle.credentials.length,
  );

  /// Applies [bundle] per [options]. Throws [BackupOlderSchemaException]
  /// without touching anything if [BackupBundle.dbVersion] is newer than
  /// this device's own schema — every other section restores by upserting
  /// on the row's own id (see [RestoreOptions]'s own doc for why that's
  /// already the merge policy, not a separate mode), so partial application
  /// on an earlier failure is never worse than "some of the newest export
  /// wasn't applied yet," not data loss.
  Future<void> restore(BackupBundle bundle, RestoreOptions options) async {
    if (bundle.dbVersion > AppConstants.dbVersion) {
      throw BackupOlderSchemaException(bundle.dbVersion, AppConstants.dbVersion);
    }

    if (options.applySettings) {
      final restored = bundle.settings;
      if (restored != null) await _applySettings(restored);
    }
    if (options.applyTones) {
      for (final tone in bundle.tones) {
        await configStore.upsertTone(tone);
      }
    }
    if (options.applyAudiences) {
      for (final audience in bundle.audiences) {
        await configStore.upsertAudience(audience);
      }
    }
    if (options.applyWorkflows) {
      for (final workflow in bundle.workflows) {
        await workflowRegistry.save(workflow);
      }
    }
    if (options.applyProviderConfigs) {
      for (final config in bundle.providerConfigs) {
        await providerRegistry.save(config);
      }
    }
    if (options.applyCredentials) {
      for (final credential in bundle.credentials) {
        await credentialStore.write(credential.ref, credential.secret);
      }
    }
    switch (options.history) {
      case HistoryRestoreStrategy.skip:
        break;
      case HistoryRestoreStrategy.append:
        await storage.appendHistory(bundle.history);
      case HistoryRestoreStrategy.replace:
        await storage.replaceHistory(bundle.history);
    }
  }

  /// Writes every [BackupSettings] field straight through `SettingsService`
  /// — `services/` never depends on `state/`, so this cannot notify
  /// `SettingsController` itself. The caller (the import screen) is
  /// expected to call `SettingsController.refreshFromService()` once the
  /// whole restore finishes, the same way `ConfigStore`/`WorkflowRegistry`/
  /// `ProviderRegistry` already notify themselves through their own
  /// `upsert`/`save` calls above.
  Future<void> _applySettings(BackupSettings restored) async {
    await settings.setThemeMode(restored.themeMode);
    await settings.setThreads(restored.threads);
    await settings.setUseGpu(restored.useGpu);
    await settings.setContextSize(restored.contextSize);
    await settings.setWhisperModel(restored.whisperModel);
    await settings.setProcessingMode(
      ProcessingMode.values.firstWhere(
        (m) => m.name == restored.processingMode,
        orElse: () => ProcessingMode.local,
      ),
    );
    await settings.setUiMode(
      UiMode.values.firstWhere(
        (m) => m.name == restored.uiMode,
        orElse: () => UiMode.simple,
      ),
    );
    await settings.setCloudProviderId(restored.cloudProviderId);
    await settings.setCloudModelRef(restored.cloudModelRef);
    await settings.setSpeechEngine(restored.speechEngine);
  }

  /// The filename (without a path) a fresh export should use — sortable by
  /// name, and self-describing if someone finds it outside the app.
  static String suggestedFileName(DateTime at) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'rescripto-backup-${at.year}${pad(at.month)}${pad(at.day)}-'
        '${pad(at.hour)}${pad(at.minute)}.rescriptobackup';
  }
}
