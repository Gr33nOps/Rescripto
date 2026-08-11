import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'credential_ref.dart';
import 'secure_storage.dart';

/// BYO API keys and similar secrets, namespaced by [CredentialRef].
///
/// The secret itself lives only in the platform Keystore, via [SecureStorage].
/// SQLite holds a parallel, deliberately non-secret index (`credential_ref`)
/// — see the migration's own doc comment — so the settings UI can list what's
/// configured without ever touching plaintext, and so [deleteAll] has a list
/// of keys to sweep rather than needing a slow read of the whole secure store.
class CredentialStore {
  CredentialStore(this._database, {SecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorageAdapter();

  final AppDatabase _database;
  final SecureStorage _storage;

  Future<bool> has(CredentialRef ref) async {
    final db = await _database.db;
    final rows = await db.query(
      'credential_ref',
      where: 'provider_id = ? AND account_id = ? AND kind = ?',
      whereArgs: [ref.providerId, ref.accountId, ref.kind.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns null if nothing is stored — or if the platform Keystore
  /// couldn't be read at all, e.g. a key invalidated by a device restore.
  /// Callers must treat both cases identically: "not configured," never a
  /// crash. This is the one place that degradation is enforced; every
  /// caller downstream gets the same simple contract regardless of why the
  /// secret isn't available.
  Future<String?> read(CredentialRef ref) async {
    try {
      return await _storage.read(ref.storageKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(CredentialRef ref, String secret, {String? label}) async {
    await _storage.write(ref.storageKey, secret);
    final db = await _database.db;
    await db.insert('credential_ref', {
      'provider_id': ref.providerId,
      'account_id': ref.accountId,
      'kind': ref.kind.name,
      'label': label,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(CredentialRef ref) async {
    // Best-effort: a Keystore that can't be read can't be written to either,
    // and the index row is removed regardless so the ref stops being listed
    // as configured.
    try {
      await _storage.delete(ref.storageKey);
    } catch (_) {}
    final db = await _database.db;
    await db.delete(
      'credential_ref',
      where: 'provider_id = ? AND account_id = ? AND kind = ?',
      whereArgs: [ref.providerId, ref.accountId, ref.kind.name],
    );
  }

  /// Every ref currently indexed — ids only, never a secret value. What a
  /// settings screen renders "OpenAI — key configured" from.
  Future<List<CredentialRef>> listRefs() async {
    final db = await _database.db;
    final rows = await db.query('credential_ref');
    return rows
        .map(
          (row) => CredentialRef(
            providerId: row['provider_id'] as String,
            accountId: row['account_id'] as String,
            kind: CredentialKind.values.byName(row['kind'] as String),
          ),
        )
        .toList();
  }

  /// Wipes every stored secret: each indexed ref individually, then a full
  /// sweep of the secure store for anything the index missed. Returns how
  /// many indexed refs were removed.
  Future<int> deleteAll() async {
    final refs = await listRefs();
    for (final ref in refs) {
      try {
        await _storage.delete(ref.storageKey);
      } catch (_) {}
    }
    try {
      await _storage.deleteAll();
    } catch (_) {}

    final db = await _database.db;
    return db.delete('credential_ref');
  }
}
