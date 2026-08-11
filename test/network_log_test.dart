import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/network_log_entry.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_log.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late NetworkLog log;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rescripto_network_log');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    log = NetworkLog(database);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('NetworkLog.open / close', () {
    test('a completed request is recorded with its outcome', () async {
      final id = await log.open(
        feature: NetworkFeature.modelDownload,
        method: 'GET',
        host: 'huggingface.co',
        path: '/org/model/resolve/main/model.gguf',
        purpose: 'Download Gemma 3 1B',
      );
      await log.close(
        id,
        outcome: NetworkOutcome.allowed,
        statusCode: 200,
        duration: const Duration(milliseconds: 42),
        bytesReceived: 1024,
      );

      final rows = await log.recent();
      expect(rows, hasLength(1));
      final entry = rows.single;
      expect(entry.feature, NetworkFeature.modelDownload);
      expect(entry.host, 'huggingface.co');
      expect(entry.outcome, NetworkOutcome.allowed);
      expect(entry.statusCode, 200);
      expect(entry.bytesReceived, 1024);
      expect(entry.purpose, 'Download Gemma 3 1B');
    });

    test('never stores a query string, even when the request had one', () async {
      final id = await log.open(
        feature: NetworkFeature.modelDownload,
        method: 'GET',
        host: 'api.example.com',
        // A caller must pass Uri.path, not the full URL — but even if a
        // query string slipped in here, the point is this class has no
        // column that would keep it around for a caller to export.
        path: Uri.parse('https://api.example.com/v1/models?key=super-secret').path,
      );
      await log.close(id, outcome: NetworkOutcome.allowed);

      final entry = (await log.recent()).single;
      expect(entry.path, '/v1/models');
      expect(entry.path, isNot(contains('key')));
      expect(entry.path, isNot(contains('secret')));
    });
  });

  group('NetworkLog.record', () {
    test('writes one row for a request blocked before it ever opened', () async {
      await log.record(
        feature: NetworkFeature.cloudRewrite,
        method: 'POST',
        host: 'api.openai.com',
        path: '/v1/chat/completions',
        outcome: NetworkOutcome.blockedByPolicy,
      );

      final entry = (await log.recent()).single;
      expect(entry.outcome, NetworkOutcome.blockedByPolicy);
      expect(entry.statusCode, isNull);
    });
  });

  group('NetworkLog pruning', () {
    test('caps at maxRows, keeping the most recent', () async {
      // A small injected cap, rather than the real ~1000-row default,
      // keeps this test from writing a thousand rows just to exercise the
      // one branch that only fires once the cap is crossed.
      final cappedLog = NetworkLog(database, maxRows: 5);
      const totalWritten = 8;
      for (var i = 0; i < totalWritten; i++) {
        await cappedLog.record(
          feature: NetworkFeature.modelDownload,
          method: 'GET',
          host: 'huggingface.co',
          path: '/req-$i',
          outcome: NetworkOutcome.allowed,
        );
      }

      final db = await database.db;
      final count = await db.rawQuery('SELECT COUNT(*) AS n FROM network_log');
      expect(count.first['n'], 5);

      final newest = (await cappedLog.recent(limit: 1)).single;
      expect(newest.path, '/req-${totalWritten - 1}');
    });
  });

  group('NetworkLog.clear', () {
    test('removes every row', () async {
      await log.record(
        feature: NetworkFeature.modelDownload,
        method: 'GET',
        host: 'huggingface.co',
        path: '/x',
        outcome: NetworkOutcome.allowed,
      );
      await log.clear();
      expect(await log.recent(), isEmpty);
    });
  });
}
