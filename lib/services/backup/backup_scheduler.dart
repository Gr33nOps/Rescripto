import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../credentials/credential_ref.dart';
import '../credentials/credential_store.dart';
import '../settings_service.dart';
import 'backup_service.dart';

/// Writes an unattended, encrypted local backup on app start once
/// [SettingsService.scheduledBackupsEnabled] is on and the interval has
/// elapsed — the in-app-timer half of the plan's "workmanager or an
/// in-app timer on next launch," chosen over `workmanager` deliberately:
/// a background task scheduler earns its cost (a foreground service,
/// battery-optimization exemptions, a whole platform-channel surface) once
/// a backup genuinely cannot wait for the next time the user opens the
/// app. Nothing about "keep a recent local copy" needs that — the app is
/// already running by the time [runIfDue] is called.
///
/// Never touches external storage — the backup lands in the same
/// application-support directory `LocalLlmService` already uses for model
/// files, which is private to this app and excluded from Android's
/// (disabled) auto-backup the same way `rescripto.db` already is.
class BackupScheduler {
  BackupScheduler({
    required this.settings,
    required this.backupService,
    required this.credentialStore,
    Future<Directory> Function()? backupsDirectory,
  }) : _backupsDirectoryOverride = backupsDirectory;

  final SettingsService settings;
  final BackupService backupService;
  final CredentialStore credentialStore;

  /// Lets a test point backups at a temp directory instead of the real
  /// application-support directory, which needs a platform channel
  /// `getApplicationSupportDirectory` has no fake for in a plain host test.
  final Future<Directory> Function()? _backupsDirectoryOverride;

  /// Shared with `SyncService` — a sync push/pull needs a passphrase with
  /// no user present to type one in, the same constraint that motivated
  /// this ref for scheduled backups in the first place. Splitting them
  /// into two separately-remembered secrets would add friction without
  /// adding security: both are "encrypt this content at rest with a
  /// device-chosen passphrase," as opposed to the WebDAV account password,
  /// which authenticates to the server and never touches the bundle's
  /// contents at all.
  static const passphraseRef = CredentialRef(
    providerId: 'device',
    kind: CredentialKind.backupPassphrase,
  );

  /// How often a scheduled backup may run. Not user-configurable — one
  /// less settings surface to design for a feature whose whole point is to
  /// require no attention.
  static const Duration interval = Duration(days: 7);

  /// How many scheduled backups to keep before deleting the oldest.
  static const int retentionCount = 5;

  static const String backupsDirName = 'backups';

  /// Call once per app start, after the provider tree exists. A no-op
  /// unless scheduling is on, a passphrase has been set (see
  /// [setPassphrase]), and [interval] has elapsed since
  /// [SettingsService.lastScheduledBackupAt]. Failures are swallowed —
  /// a scheduled backup must never be the reason app start fails.
  Future<void> runIfDue() async {
    if (!settings.scheduledBackupsEnabled) return;

    final last = settings.lastScheduledBackupAt;
    if (last != null && DateTime.now().difference(last) < interval) return;

    final passphrase = await credentialStore.read(passphraseRef);
    if (passphrase == null) return;

    try {
      final bundle = await backupService.gather(
        includeHistory: settings.scheduledBackupIncludeHistory,
        includeCredentials: settings.scheduledBackupIncludeCredentials,
      );
      final fileBytes = await backupService.export(bundle, passphrase);

      final dir = await _backupsDirectory();
      final fileName = BackupService.suggestedFileName(bundle.createdAt);
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(fileBytes);

      await _enforceRetention(dir);
      await settings.setLastScheduledBackupAt(bundle.createdAt);
    } catch (_) {
      // Best-effort. The next launch tries again.
    }
  }

  Future<bool> hasPassphrase() => credentialStore.has(passphraseRef);

  Future<void> setPassphrase(String passphrase) =>
      credentialStore.write(passphraseRef, passphrase);

  Future<void> clearPassphrase() => credentialStore.delete(passphraseRef);

  Future<Directory> _backupsDirectory() async {
    final override = _backupsDirectoryOverride;
    if (override != null) return override();

    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}$backupsDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _enforceRetention(Directory dir) async {
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    while (files.length > retentionCount) {
      final oldest = files.removeAt(0);
      await oldest.delete();
    }
  }
}
