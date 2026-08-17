import '../../models/backup_bundle.dart';
import '../backup/backup_service.dart';
import '../credentials/credential_ref.dart';
import '../credentials/credential_store.dart';
import '../network/network_feature.dart';
import '../network/network_guard.dart';
import '../settings_service.dart';
import 'webdav_client.dart';
import 'webdav_exception.dart';
import 'webdav_sync_conflict_exception.dart';

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

  Uri get _remoteUrl => _resolveRemoteUrl(settings.webdavUrl!);

  /// Builds the one remote file's URL from [baseUrl], validating it first.
  ///
  /// `Uri.parse` alone accepts strings no WebDAV request could ever use —
  /// no scheme, no host — and previously threw an uncaught `FormatException`
  /// straight out of [push]/[pull] the first time a malformed saved URL was
  /// used, since neither catches anything but [WebDavException]. Validating
  /// here means every caller gets the same typed [WebDavException] instead.
  Uri _resolveRemoteUrl(String baseUrl) {
    final Uri base;
    try {
      base = Uri.parse(baseUrl);
    } on FormatException {
      throw const WebDavException(null, 'The server URL is not valid.');
    }
    if (!(base.scheme == 'http' || base.scheme == 'https') || base.host.isEmpty) {
      throw const WebDavException(
        null,
        'The server URL must start with http:// or https:// and include a host.',
      );
    }
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$basePath$_remoteFileName');
  }

  /// Checks that [baseUrl]/[username] (with the already-saved password) can
  /// reach the server, without persisting [baseUrl] or [username] anywhere.
  ///
  /// The sync screen's "Test connection" button used to call this by first
  /// writing the typed URL/username into [SettingsService] and *then*
  /// testing — so a failed test still left the new values saved, even
  /// though a separate "Save" button exists specifically to make that an
  /// explicit action. Taking the values as parameters instead of reading
  /// them off [settings] is what makes that impossible by construction.
  Future<void> testConnection(String baseUrl, String username) async {
    final url = _resolveRemoteUrl(baseUrl);
    await client.lastModified(url, username, await _password());
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
  ///
  /// Records the remote file's current ETag/timestamp as this device's
  /// confirmed state, same as [push] does after uploading — a device that
  /// just pulled has genuinely seen the latest copy, so its *next* push
  /// should not be flagged as a conflict against itself.
  Future<BackupBundle> pull(String passphrase) async {
    final url = _remoteUrl;
    final username = settings.webdavUsername ?? '';
    final password = await _password();
    final bytes = await client.get(url, username, password);
    if (bytes == null) {
      throw const WebDavException(404, 'Nothing has been synced to this server yet.');
    }
    await _recordKnownRemoteState(url, username, password);
    return backupService.decrypt(bytes, passphrase);
  }

  /// Gathers local state per the caller's section selection and uploads it,
  /// overwriting whatever was there. Records the bundle's own `createdAt`
  /// as the new "last pushed" mark, so a later [remoteNewerThanLastPush]
  /// on *this* device correctly sees its own push as not-newer (it's
  /// comparing against itself) while a second device's later push still
  /// shows up as ahead.
  ///
  /// Unconditional PUT used to be the whole story — Device A pushing after
  /// Device B had already pushed a newer copy would silently overwrite B's
  /// data, and the sync screen's "server has a newer copy" banner was only
  /// ever advisory: nothing stopped "Sync now" from proceeding anyway. This
  /// now checks the server's current state against what this device last
  /// confirmed (see [_conflictsWithKnownState]) immediately before writing,
  /// and throws [WebDavSyncConflictException] instead of overwriting unless
  /// the caller passes [force]. [WebDavClient.put]'s own `If-Match` closes
  /// the remaining gap between that check and the write for servers that
  /// support ETags — a race that check alone cannot fully close.
  Future<void> push(
    String passphrase, {
    bool includeSettings = true,
    bool includeTones = true,
    bool includeAudiences = true,
    bool includeWorkflows = true,
    bool includeProviderConfigs = true,
    bool includeHistory = false,
    bool includeCredentials = false,
    bool force = false,
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

    final url = _remoteUrl;
    final username = settings.webdavUsername ?? '';
    final password = await _password();

    final remote = await client.stat(url, username, password);
    if (!force && _conflictsWithKnownState(remote)) {
      throw WebDavSyncConflictException(remote.lastModified);
    }

    try {
      await client.put(url, username, password, fileBytes, ifMatchEtag: force ? null : remote.etag);
    } on WebDavException catch (e) {
      if (e.isConflict) throw WebDavSyncConflictException(remote.lastModified);
      rethrow;
    }
    await settings.setLastSyncPushAt(bundle.createdAt);
    await _recordKnownRemoteState(url, username, password);
  }

  /// True when the server's file has moved on from what this device last
  /// confirmed, meaning a push would overwrite a change it has never seen.
  ///
  /// Prefers ETag comparison — an exact identity check, immune to two
  /// devices' clocks disagreeing — and falls back to the `getlastmodified`
  /// timestamp only when either side lacks an ETag (a server that doesn't
  /// return `getetag`, or a device that has never recorded one).
  bool _conflictsWithKnownState(({DateTime? lastModified, String? etag}) remote) {
    if (remote.lastModified == null && remote.etag == null) return false;

    final knownEtag = settings.lastSyncEtag;
    if (remote.etag != null && knownEtag != null) {
      return remote.etag != knownEtag;
    }

    final knownAt = settings.lastKnownRemoteAt;
    if (knownAt == null) return true;
    final remoteAt = remote.lastModified;
    return remoteAt != null && remoteAt.isAfter(knownAt);
  }

  /// Records the server's current ETag/timestamp as this device's confirmed
  /// baseline for [_conflictsWithKnownState]. Re-stats rather than reusing
  /// an earlier [WebDavClient.stat] call so the recorded state is always
  /// the one actually on the server after a write, not the one queried
  /// before it (a PUT response rarely carries a trustworthy new ETag on
  /// every WebDAV server, so this is one more request rather than an
  /// assumption).
  Future<void> _recordKnownRemoteState(Uri url, String username, String password) async {
    final remote = await client.stat(url, username, password);
    await settings.setLastSyncEtag(remote.etag);
    await settings.setLastKnownRemoteAt(remote.lastModified);
  }

  Future<String> _password() async {
    final password = await credentialStore.read(passwordRef);
    if (password == null) {
      throw const WebDavException(401, 'No WebDAV password configured.');
    }
    return password;
  }
}
