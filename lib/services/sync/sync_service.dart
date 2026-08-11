import '../../models/backup_bundle.dart';
import '../backup/backup_service.dart';
import '../credentials/credential_ref.dart';
import '../credentials/credential_store.dart';
import '../network/network_feature.dart';
import '../network/network_guard.dart';
import '../settings_service.dart';
import 'webdav_client.dart';
import 'webdav_exception.dart';

/// One fixed remote file is the whole sync surface — not a folder of
/// individual rows. The server is untrusted by assumption (that's the
/// entire reason it only ever receives [BackupService.export]'s encrypted
/// bytes, never a raw table), so there is nothing for it to inspect or
/// partially update; PUT replaces the file outright and GET reads it back
/// whole.
class SyncService {
  SyncService({
    required this.settings,
    required this.backupService,
    required this.credentialStore,
    required this.client,
  });

  /// The production constructor: builds [client] from
  /// `NetworkGuard.httpClientFor(NetworkFeature.sync)`, so every sync
  /// request is policy-checked and logged the same as any other egress.
  /// A test constructs [SyncService] directly with a [WebDavClient]
  /// wrapping a fake `http.Client` instead — no `NetworkGuard` needed.
  factory SyncService.withGuard({
    required SettingsService settings,
    required BackupService backupService,
    required CredentialStore credentialStore,
    required NetworkGuard networkGuard,
  }) {
    return SyncService(
      settings: settings,
      backupService: backupService,
      credentialStore: credentialStore,
      client: WebDavClient(networkGuard.httpClientFor(NetworkFeature.sync, purpose: 'Sync backup')),
    );
  }

  final SettingsService settings;
  final BackupService backupService;
  final CredentialStore credentialStore;
  final WebDavClient client;

  static const passwordRef = CredentialRef(providerId: 'webdav', kind: CredentialKind.webdavPassword);
  static const _remoteFileName = 'rescripto-sync.rescriptobackup';

  bool get isConfigured => settings.webdavUrl != null && settings.webdavUrl!.isNotEmpty;

  Uri get _remoteUrl {
    final base = Uri.parse(settings.webdavUrl!);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$basePath$_remoteFileName');
  }

  /// Whether the server holds a copy newer than the last one this device
  /// pushed — the "server is newer" signal the sync screen turns into a
  /// visible prompt rather than ever auto-applying. Null means either
  /// there's nothing to compare (no remote file yet, this device has never
  /// pushed) or the server isn't ahead — either way, nothing to show.
  Future<DateTime?> remoteNewerThanLastPush() async {
    final remoteModified = await client.lastModified(
      _remoteUrl,
      settings.webdavUsername ?? '',
      await _password(),
    );
    if (remoteModified == null) return null;
    final lastPush = settings.lastSyncPushAt;
    if (lastPush != null && !remoteModified.isAfter(lastPush)) return null;
    return remoteModified;
  }

  /// Downloads and decrypts the remote bundle. The caller previews it via
  /// `BackupService.preview` and applies it via `BackupService.restore` —
  /// exactly the same two calls the Import screen already makes on a
  /// locally-picked file, because a pulled sync bundle and an imported
  /// backup file are the same shape by construction.
  Future<BackupBundle> pull(String passphrase) async {
    final bytes = await client.get(_remoteUrl, settings.webdavUsername ?? '', await _password());
    if (bytes == null) {
      throw const WebDavException(404, 'Nothing has been synced to this server yet.');
    }
    return backupService.decrypt(bytes, passphrase);
  }

  /// Gathers local state per the caller's section selection and uploads it,
  /// overwriting whatever was there. Records the bundle's own `createdAt`
  /// as the new "last pushed" mark, so a later [remoteNewerThanLastPush]
  /// on *this* device correctly sees its own push as not-newer (it's
  /// comparing against itself) while a second device's later push still
  /// shows up as ahead.
  Future<void> push(
    String passphrase, {
    bool includeSettings = true,
    bool includeTones = true,
    bool includeAudiences = true,
    bool includeWorkflows = true,
    bool includeProviderConfigs = true,
    bool includeHistory = false,
    bool includeCredentials = false,
  }) async {
    final bundle = await backupService.gather(
      includeSettings: includeSettings,
      includeTones: includeTones,
      includeAudiences: includeAudiences,
      includeWorkflows: includeWorkflows,
      includeProviderConfigs: includeProviderConfigs,
      includeHistory: includeHistory,
      includeCredentials: includeCredentials,
    );
    final fileBytes = await backupService.export(bundle, passphrase);
    await client.put(_remoteUrl, settings.webdavUsername ?? '', await _password(), fileBytes);
    await settings.setLastSyncPushAt(bundle.createdAt);
  }

  Future<String> _password() async {
    final password = await credentialStore.read(passwordRef);
    if (password == null) {
      throw const WebDavException(401, 'No WebDAV password configured.');
    }
    return password;
  }
}
