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

  /// Inserts every entry in [entries] as one all-or-nothing unit.
  ///
  /// A restore's append step used to insert rows one at a time with no
  /// transaction — a failure partway through (a malformed record, a full
  /// disk) left whatever had already committed in place with no way to tell
  /// the restore was incomplete. A transaction makes the failure mode "none
  /// of it happened" instead.
  Future<void> appendHistory(List<HistoryEntry> entries) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      for (final entry in entries) {
        await txn.insert('history', entry.toMap(includeId: false));
      }
    });
  }

  /// Clears existing history and inserts [entries] as one all-or-nothing
  /// unit.
  ///
  /// A restore's replace step used to call [clearHistory] and then insert
  /// the backup's rows one at a time, each its own committed statement. A
  /// failure partway through the inserts — a malformed record, a full disk,
  /// a SQLite error — left the clear committed and only part of the backup
  /// restored: the user's previous history was already gone, permanently,
  /// for a run that as far as the UI could tell had simply failed. Wrapping
  /// the whole sequence in one transaction means a failure rolls back the
  /// clear along with every insert, leaving the previous history intact.
  Future<void> replaceHistory(List<HistoryEntry> entries) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      await txn.delete('history');
      for (final entry in entries) {
        await txn.insert('history', entry.toMap(includeId: false));
      }
    });
  }
}
