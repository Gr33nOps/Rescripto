import 'package:sqflite/sqflite.dart';

import '../../models/provider_config.dart';
import '../credentials/credential_store.dart';
import '../db/app_database.dart';

/// Raw SQLite persistence for [ProviderConfig] and its per-config model list.
///
/// `ProviderRegistry` is the in-memory, `ChangeNotifier` cache the rest of
/// the app reads from; this is what it persists through. Split out mainly so
/// deleting a provider's credential has one obvious place to happen: SQLite's
/// `ON DELETE CASCADE` removes the `provider_model` rows on its own, but it
/// cannot reach into the platform Keystore, so [delete] calls
/// [CredentialStore.delete] itself, right next to the row delete it must
/// always accompany.
class ProviderStore {
  ProviderStore(this._database, this._credentialStore);

  final AppDatabase _database;
  final CredentialStore _credentialStore;

  Future<List<ProviderConfig>> loadAll() async {
    final db = await _database.db;
    final rows = await db.query('provider_config', orderBy: 'created_at');
    final configs = <ProviderConfig>[];
    for (final row in rows) {
      final models = await _loadModels(db, row['id'] as String);
      configs.add(ProviderConfig.fromMap(row, models: models));
    }
    return configs;
  }

  Future<void> upsert(ProviderConfig config) async {
    ProviderConfig.validateExtraHeaders(config.extraHeaders);
    final db = await _database.db;
    await db.insert(
      'provider_config',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _replaceModels(db, config.id, config.models);
  }

  /// Removes the config row, its models (via cascade), and its credential.
  /// A no-op if [id] isn't found.
  Future<void> delete(String id) async {
    final db = await _database.db;
    final rows = await db.query(
      'provider_config',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final config = ProviderConfig.fromMap(rows.first);
    await _credentialStore.delete(config.credential);
    await db.delete('provider_config', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ProviderModelEntry>> _loadModels(
    DatabaseExecutor db,
    String providerConfigId,
  ) async {
    final rows = await db.query(
      'provider_model',
      where: 'provider_config_id = ?',
      whereArgs: [providerConfigId],
      orderBy: 'sort_order',
    );
    return rows.map(ProviderModelEntry.fromMap).toList();
  }

  Future<void> _replaceModels(
    DatabaseExecutor db,
    String providerConfigId,
    List<ProviderModelEntry> models,
  ) async {
    final batch = db.batch();
    batch.delete(
      'provider_model',
      where: 'provider_config_id = ?',
      whereArgs: [providerConfigId],
    );
    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      batch.insert('provider_model', {
        'id': '$providerConfigId::${model.modelRef}',
        'provider_config_id': providerConfigId,
        'model_ref': model.modelRef,
        'display_name': model.displayName,
        'sort_order': i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
