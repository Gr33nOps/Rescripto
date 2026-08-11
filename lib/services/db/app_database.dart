import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import 'migrations.dart';

/// Owns the SQLite connection and the schema version it is opened at.
///
/// Split out of `StorageService` so that the stores added later — tone
/// presets, the network log, the credential index — share one connection and
/// one migration path instead of each opening a database of its own.
class AppDatabase {
  AppDatabase({
    this.migrations = kMigrations,
    this.version = AppConstants.dbVersion,
    @visibleForTesting String? path,
  }) : _pathOverride = path;

  /// Forward migrations keyed by the version each produces. Injectable so the
  /// runner can be exercised against a synthetic schema without dragging the
  /// production database through throwaway versions.
  final Map<int, Migration> migrations;

  /// Schema version this build opens the database at.
  final int version;

  /// Bypasses `getDatabasesPath()` when set, so a store built on [db] — like
  /// `ConfigStore` — can be tested against an isolated temp file through the
  /// exact same open path production uses, rather than every dependent
  /// needing its own way to reach [openAt] directly.
  final String? _pathOverride;

  Database? _db;
  Future<Database>? _opening;

  /// The open connection, opening it on first use.
  ///
  /// Memoizes the in-flight future rather than the result, so two concurrent
  /// callers share one open instead of racing to open the file twice.
  Future<Database> get db => _opening ??= _openTracked();

  Future<Database> _openTracked() async {
    try {
      final database = await _open();
      _db = database;
      return database;
    } catch (_) {
      // Don't latch the failure. A transient open error — a locked file, a
      // full disk — should be retryable on the next call rather than leaving
      // every later caller holding the same rejected future.
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final override = _pathOverride;
    if (override != null) return openAt(override);
    final dir = await getDatabasesPath();
    return openAt(p.join(dir, AppConstants.dbName));
  }

  /// Opens (and migrates) the database at [path].
  @visibleForTesting
  Future<Database> openAt(String path) async {
    await _preserveIfNewer(path);
    return openDatabase(
      path,
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, target) async {
        // Replay the baseline and then every migration, rather than creating
        // the current schema directly. It costs milliseconds once, and it
        // removes the whole class of bug where a fresh install ends up with a
        // subtly different schema than an upgraded one.
        await createBaseline(db);
        await _applyRange(db, 1, target);
      },
      onUpgrade: _applyRange,
      onDowngrade: _refuseDowngrade,
    );
  }

  /// Applies every migration in `(from, to]`, in ascending order.
  Future<void> _applyRange(Database db, int from, int to) async {
    for (var step = from + 1; step <= to; step++) {
      final migration = migrations[step];
      if (migration == null) {
        throw StateError(
          'No migration registered for database version $step. Every version '
          'from 2 to $version needs an entry in kMigrations.',
        );
      }
      await migration(db);
    }
  }

  /// Moves aside a database written by a newer build of the app.
  ///
  /// sqflite's stock remedy for a downgrade, `onDatabaseDowngradeDelete`,
  /// destroys the file. This database is the only copy of the user's history,
  /// so installing an older APK must not be able to erase it. Renaming keeps
  /// the data recoverable by hand or by a later release, and lets the older
  /// build start on a schema it actually understands.
  Future<void> _preserveIfNewer(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;

    final existing = await _readVersion(path);
    if (existing == null || existing <= version) return;

    final backup = File('$path.v$existing.bak');
    if (backup.existsSync()) await backup.delete();
    await file.rename(backup.path);
  }

  /// Reads the schema version without triggering create or upgrade hooks.
  ///
  /// Returns null when the file cannot be read as a database at all, in which
  /// case the normal open path will surface the real error.
  Future<int?> _readVersion(String path) async {
    Database? probe;
    try {
      // No `version:` argument, so sqflite runs neither onCreate nor onUpgrade.
      probe = await openDatabase(path);
      return await probe.getVersion();
    } catch (_) {
      return null;
    } finally {
      await probe?.close();
    }
  }

  /// Unreachable while [_preserveIfNewer] does its job — kept as a tripwire.
  ///
  /// Throwing fails the open, which every caller already degrades gracefully
  /// around. That is the right trade against the alternative, which is
  /// deleting the user's only copy of their history.
  Future<void> _refuseDowngrade(Database db, int from, int to) async {
    throw StateError(
      'Database is at version $from but this build supports $to. Refusing to '
      'downgrade in place; the file should have been preserved before opening.',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
