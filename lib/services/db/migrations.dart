import 'package:sqflite/sqflite.dart';

/// A single forward schema step.
///
/// Runs inside the transaction sqflite already wraps around `onCreate` and
/// `onUpgrade`, so migrations must not open one of their own — and a throw
/// anywhere in the sequence rolls the whole upgrade back atomically.
typedef Migration = Future<void> Function(Database db);

/// The schema as it shipped through 1.0.3, before this runner existed.
///
/// Frozen. New tables and columns arrive as entries in [kMigrations], never as
/// edits here: a fresh install replays this baseline and then every migration
/// in turn, so editing it would silently diverge new installs from upgraded
/// ones — the exact drift the replay is designed to prevent.
Future<void> createBaseline(Database db) async {
  await db.execute('''
    CREATE TABLE history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      original TEXT NOT NULL,
      rewritten TEXT NOT NULL,
      tone_id TEXT NOT NULL,
      intensity TEXT,
      length TEXT,
      created_at TEXT NOT NULL
    )
  ''');
}

/// Tone presets and audience tags, moved out of `static const` Dart lists so
/// they can be edited and, later, backed up. `is_builtin`/`seed_version`/
/// `user_modified` let `ConfigSeeder` refresh built-in copy on a future
/// release without overwriting anything the user has changed. `is_hidden` is
/// how a built-in gets "deleted" without losing the seed row to re-hide
/// against next launch.
///
/// `idx_history_created_at` rides along here rather than waiting for its own
/// migration: `StorageService.getHistory`'s `ORDER BY created_at DESC` has
/// been a full table scan since 1.0.3's paging, and there is no reason to
/// carry that forward into a release that touches this table anyway.
Future<void> _v2ConfigTables(Database db) async {
  await db.execute('''
    CREATE TABLE tone_preset (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      icon_token    TEXT NOT NULL,
      description   TEXT NOT NULL DEFAULT '',
      instruction   TEXT NOT NULL,
      temperature   REAL NOT NULL,
      is_builtin    INTEGER NOT NULL DEFAULT 0,
      is_hidden     INTEGER NOT NULL DEFAULT 0,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      seed_version  INTEGER NOT NULL DEFAULT 0,
      user_modified INTEGER NOT NULL DEFAULT 0,
      updated_at    TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE audience_tag (
      id            TEXT PRIMARY KEY,
      label         TEXT NOT NULL,
      is_builtin    INTEGER NOT NULL DEFAULT 0,
      is_hidden     INTEGER NOT NULL DEFAULT 0,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      seed_version  INTEGER NOT NULL DEFAULT 0,
      user_modified INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_history_created_at ON history(created_at DESC)',
  );
}

/// An audit trail of outbound requests, written by `NetworkLog`.
///
/// Deliberately has no column for a request header or body, and `path` is
/// populated from `Uri.path` alone — the query string is never read, let
/// alone stored. That is structural, not disciplined: a column that does not
/// exist cannot leak a Gemini-style `?key=...` API key into a table the user
/// can export. See `lib/models/network_log_entry.dart`.
Future<void> _v3NetworkLog(Database db) async {
  await db.execute('''
    CREATE TABLE network_log (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      feature        TEXT NOT NULL,
      method         TEXT NOT NULL,
      host           TEXT NOT NULL,
      path           TEXT NOT NULL,
      purpose        TEXT,
      started_at     TEXT NOT NULL,
      duration_ms    INTEGER,
      status_code    INTEGER,
      bytes_received INTEGER,
      outcome        TEXT NOT NULL
    )
  ''');
}

/// A non-secret index of which credentials exist, written by
/// `CredentialStore`. The actual secret lives only in the platform Keystore
/// (`flutter_secure_storage`), keyed by `CredentialRef.storageKey` — this
/// table has no column that could hold one. It exists so the settings UI can
/// render "OpenAI — key configured" without touching plaintext, and so
/// `CredentialStore.deleteAll` has a list to sweep without a slow
/// `readAll()` across the whole secure store.
Future<void> _v4CredentialIndex(Database db) async {
  await db.execute('''
    CREATE TABLE credential_ref (
      provider_id TEXT NOT NULL,
      account_id  TEXT NOT NULL,
      kind        TEXT NOT NULL,
      label       TEXT,
      created_at  TEXT NOT NULL,
      PRIMARY KEY (provider_id, account_id, kind)
    )
  ''');
}

/// Configured cloud providers and the models a user has added to them.
///
/// No column here can hold a secret, matching every migration before it:
/// `credential_provider_id`/`credential_account_id`/`credential_kind` are a
/// [CredentialRef] — a lookup key into the platform Keystore, not a value.
/// The one column that could theoretically carry something sensitive is
/// `extra_headers`, and every write to it goes through
/// `ProviderConfig.validateExtraHeaders`, which rejects anything that looks
/// like an auth header before it reaches SQLite.
///
/// `provider_model` cascades on `provider_config` deletion — SQLite can do
/// that part on its own via the foreign key `AppDatabase.openAt` already
/// turns on. What it cannot cascade into is the Keystore entry a deleted
/// provider's credential lives in; `ProviderStore.delete` calls
/// `CredentialStore.delete` itself for that half.
Future<void> _v5Providers(Database db) async {
  await db.execute('''
    CREATE TABLE provider_config (
      id                      TEXT PRIMARY KEY,
      preset_id               TEXT NOT NULL,
      display_name            TEXT NOT NULL,
      base_url_override       TEXT,
      enabled                 INTEGER NOT NULL DEFAULT 1,
      credential_provider_id  TEXT NOT NULL,
      credential_account_id   TEXT NOT NULL,
      credential_kind         TEXT NOT NULL,
      extra_headers           TEXT NOT NULL DEFAULT '{}',
      created_at              TEXT NOT NULL,
      updated_at              TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE provider_model (
      id                 TEXT PRIMARY KEY,
      provider_config_id TEXT NOT NULL REFERENCES provider_config(id) ON DELETE CASCADE,
      model_ref          TEXT NOT NULL,
      display_name       TEXT NOT NULL,
      sort_order         INTEGER NOT NULL DEFAULT 0,
      UNIQUE (provider_config_id, model_ref)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_provider_model_config ON provider_model(provider_config_id)',
  );
}

/// Forward migrations, keyed by the schema version each one produces.
const Map<int, Migration> kMigrations = <int, Migration>{
  2: _v2ConfigTables,
  3: _v3NetworkLog,
  4: _v4CredentialIndex,
  5: _v5Providers,
};
