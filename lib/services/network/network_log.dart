import 'package:sqflite/sqflite.dart';

import '../../models/network_log_entry.dart';
import '../db/app_database.dart';
import 'network_feature.dart';

/// Default rolling cap. This is an audit trail for the user to glance at, not
/// a metering system — old rows are pruned rather than kept forever.
const int kDefaultNetworkLogMaxRows = 1000;

/// Persists the network audit trail `NetworkGuard` writes to.
///
/// [open], [close], and [record] are the three methods on `NetworkGuard`'s
/// critical path — called (and awaited) between a request being allowed by
/// policy and the request itself being dispatched or completed. All three
/// swallow their own failures rather than throwing: this is an audit trail
/// for the user to glance at, not a gate. Before this, a `NetworkLog` write
/// failing here (a full disk, a locked database) meant `NetworkGuard`'s
/// interceptor threw out of `onRequest`/`onResponse` — an async method dio
/// treats as a rejected/failed request regardless — so an otherwise-valid
/// cloud rewrite, model download, or WebDAV sync could fail purely because
/// its *log entry* couldn't be written. Policy enforcement itself
/// (`NetworkGuard._checkPolicy`) stays mandatory and unaffected — only the
/// logging of an already-decided outcome is best-effort. [recent] and
/// [clear] are deliberately not: those are direct user actions (viewing or
/// clearing the log), where a failure is real information the UI should see,
/// not something to hide behind a permitted request that already succeeded.
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
  ///
  /// Returns null if the write itself failed — see the class doc. [close]
  /// treats a null [id] the same way: nothing to finish.
  Future<int?> open({
    required NetworkFeature feature,
    required String method,
    required String host,
    required String path,
    String? purpose,
  }) async {
    try {
      final db = await _database.db;
      return await db.insert('network_log', {
        'feature': feature.name,
        'method': method,
        'host': host,
        'path': path,
        'purpose': purpose,
        'started_at': DateTime.now().toIso8601String(),
        'outcome': NetworkOutcome.allowed.name,
      });
    } catch (_) {
      return null;
    }
  }

  /// No-ops on a null [id] (see [open]) or on a write failure — best-effort,
  /// see the class doc.
  Future<void> close(
    int? id, {
    required NetworkOutcome outcome,
    Duration? duration,
    int? statusCode,
    int? bytesReceived,
  }) async {
    if (id == null) return;
    try {
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
    } catch (_) {
      // Best-effort — see the class doc. The request this row was tracking
      // already completed (or failed) on its own; losing this write must
      // not retroactively fail it.
    }
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
    try {
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
    } catch (_) {
      // Best-effort — see the class doc.
    }
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
