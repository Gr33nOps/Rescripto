import 'package:sqflite/sqflite.dart';

import '../../models/network_log_entry.dart';
import '../db/app_database.dart';
import 'network_feature.dart';

/// Default rolling cap. This is an audit trail for the user to glance at, not
/// a metering system — old rows are pruned rather than kept forever.
const int kDefaultNetworkLogMaxRows = 1000;

/// Persists the network audit trail `NetworkGuard` writes to.
class NetworkLog {
  NetworkLog(this._database, {this.maxRows = kDefaultNetworkLogMaxRows});

  final AppDatabase _database;

  /// Injectable so a test can exercise pruning without writing a thousand
  /// rows first.
  final int maxRows;

  /// Opens a row for a request that is actually going out, to be finished
  /// with [close] once it completes. One row per request, opened before
  /// dispatch and updated on completion — never per chunk. `ModelManager`
  /// already learned this lesson the hard way: notifying on every chunk of a
  /// 2 GB download was enough UI work to throttle the transfer itself.
  Future<int> open({
    required NetworkFeature feature,
    required String method,
    required String host,
    required String path,
    String? purpose,
  }) async {
    final db = await _database.db;
    return db.insert('network_log', {
      'feature': feature.name,
      'method': method,
      'host': host,
      'path': path,
      'purpose': purpose,
      'started_at': DateTime.now().toIso8601String(),
      'outcome': NetworkOutcome.allowed.name,
    });
  }

  Future<void> close(
    int id, {
    required NetworkOutcome outcome,
    Duration? duration,
    int? statusCode,
    int? bytesReceived,
  }) async {
    final db = await _database.db;
    await db.update(
      'network_log',
      {
        'outcome': outcome.name,
        'duration_ms': duration?.inMilliseconds,
        'status_code': statusCode,
        'bytes_received': bytesReceived,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _prune(db);
  }

  /// For a request refused before it ever went out — one write, rather than
  /// [open] immediately followed by [close].
  Future<void> record({
    required NetworkFeature feature,
    required String method,
    required String host,
    required String path,
    required NetworkOutcome outcome,
    String? purpose,
  }) async {
    final db = await _database.db;
    await db.insert('network_log', {
      'feature': feature.name,
      'method': method,
      'host': host,
      'path': path,
      'purpose': purpose,
      'started_at': DateTime.now().toIso8601String(),
      'outcome': outcome.name,
    });
    await _prune(db);
  }

  Future<List<NetworkLogEntry>> recent({int limit = 100}) async {
    final db = await _database.db;
    final rows = await db.query('network_log', orderBy: 'id DESC', limit: limit);
    return rows.map(NetworkLogEntry.fromMap).toList();
  }

  Future<void> clear() async {
    final db = await _database.db;
    await db.delete('network_log');
  }

  Future<void> _prune(DatabaseExecutor db) async {
    // Every write otherwise pays for a full-table scan + subquery, forever,
    // even when the table holds a handful of rows. A single indexed COUNT
    // first keeps the common case — nowhere near the cap — cheap.
    final counted = await db.rawQuery('SELECT COUNT(*) AS n FROM network_log');
    final count = counted.first['n'] as int;
    if (count <= maxRows) return;

    await db.rawDelete(
      'DELETE FROM network_log WHERE id NOT IN '
      '(SELECT id FROM network_log ORDER BY id DESC LIMIT ?)',
      [maxRows],
    );
  }
}
