/// How to fold [BackupBundle.history] into local history, which has no
/// natural id to upsert against — every other section restores by upserting
/// on the row's own id, which is already a merge; history needs its own
/// choice because two exports of the same install can legitimately contain
/// overlapping entries with no shared identity to de-duplicate on.
enum HistoryRestoreStrategy {
  /// Bundle history is not touched. The default — history is the most
  /// sensitive section, and skipping it is always safe.
  skip,

  /// Every bundle entry is inserted as a new local row, alongside whatever
  /// is already there. Simple, and never destroys an existing entry, at
  /// the cost of duplicates if the same backup is restored twice.
  append,

  /// Local history is cleared first, then the bundle's entries are
  /// inserted. The only strategy that can lose local-only entries — the
  /// preview screen must say so before this is offered as a choice.
  replace,
}

/// What [BackupService.restore] should actually do with a decrypted bundle.
///
/// Tones/audiences/workflows/provider configs restore by upserting on the
/// row's own id — there is no separate "replace" mode for them, because
/// upsert already is the merge policy the plan calls for: a local id absent
/// from the bundle is left untouched, one present in both is overwritten
/// with the bundle's copy. A destructive "delete anything not in the
/// bundle" mode is deliberately not offered — nothing in this app's restore
/// flow needs it, and it is a much easier way to lose local-only work than
/// any of the toggles below.
class RestoreOptions {
  const RestoreOptions({
    this.applySettings = true,
    this.applyTones = true,
    this.applyAudiences = true,
    this.applyWorkflows = true,
    this.applyProviderConfigs = true,
    this.applyCredentials = false,
    this.history = HistoryRestoreStrategy.skip,
  });

  final bool applySettings;
  final bool applyTones;
  final bool applyAudiences;
  final bool applyWorkflows;
  final bool applyProviderConfigs;

  /// Only meaningful (and only ever offered by the UI) when the bundle's
  /// own `containsSecrets` is true — there is nothing to apply otherwise.
  final bool applyCredentials;

  final HistoryRestoreStrategy history;
}

/// Summary [BackupService.preview] returns before anything is applied —
/// everything a restore screen needs to render counts and the
/// `containsSecrets` warning without touching the database.
class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.dbVersion,
    required this.containsSecrets,
    required this.hasSettings,
    required this.toneCount,
    required this.audienceCount,
    required this.workflowCount,
    required this.providerConfigCount,
    required this.historyCount,
    required this.credentialCount,
  });

  final DateTime createdAt;
  final String appVersion;
  final int dbVersion;
  final bool containsSecrets;
  final bool hasSettings;
  final int toneCount;
  final int audienceCount;
  final int workflowCount;
  final int providerConfigCount;
  final int historyCount;
  final int credentialCount;
}
