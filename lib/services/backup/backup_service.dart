import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../../models/backup_bundle.dart';
import '../config_store.dart';
import '../credentials/credential_store.dart';
import '../providers/provider_registry.dart';
import '../settings_service.dart';
import '../storage_service.dart';
import '../workflows/workflow_registry.dart';
import 'backup_crypto.dart';
import 'backup_exception.dart';

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

  /// Reads current app state into a bundle. [includeHistory] and
  /// [includeCredentials] default to false — both are opt-in even for a
  /// caller that skips the UI, so the safer bundle is always the one
  /// produced without extra arguments.
  Future<BackupBundle> gather({
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
      settings: BackupSettings(
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
      ),
      tones: configStore.tones,
      audiences: configStore.audiences,
      workflows: workflowRegistry.workflows,
      providerConfigs: providerRegistry.configs,
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

  /// The filename (without a path) a fresh export should use — sortable by
  /// name, and self-describing if someone finds it outside the app.
  static String suggestedFileName(DateTime at) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'rescripto-backup-${at.year}${pad(at.month)}${pad(at.day)}-'
        '${pad(at.hour)}${pad(at.minute)}.rescriptobackup';
  }
}
