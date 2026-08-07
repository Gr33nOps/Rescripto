import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../models/history_entry.dart';

/// SQLite storage for rewrite history. Stored only on this device.
class StorageService {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: (db, version) async {
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
      },
    );
  }

  Future<int> insertHistory(HistoryEntry entry) async {
    final db = await _database;
    return db.insert('history', entry.toMap());
  }

  Future<List<HistoryEntry>> getHistory({int limit = 200}) async {
    final db = await _database;
    final rows = await db.query(
      'history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> deleteHistory(int id) async {
    final db = await _database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await _database;
    await db.delete('history');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
