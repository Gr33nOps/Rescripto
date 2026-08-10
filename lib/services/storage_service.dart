import '../models/history_entry.dart';
import 'db/app_database.dart';

/// SQLite storage for rewrite history. Stored only on this device.
///
/// Owns the `history` table only. The connection and its schema version belong
/// to [AppDatabase], which every other store shares.
class StorageService {
  StorageService(this._database);

  final AppDatabase _database;

  Future<int> insertHistory(HistoryEntry entry) async {
    final db = await _database.db;
    return db.insert('history', entry.toMap(includeId: false));
  }

  Future<List<HistoryEntry>> getHistory({int? limit, int? offset}) async {
    final db = await _database.db;
    final rows = await db.query(
      'history',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> deleteHistory(int id) async {
    final db = await _database.db;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await _database.db;
    await db.delete('history');
  }
}
