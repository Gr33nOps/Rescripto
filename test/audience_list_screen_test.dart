import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rescripto/screens/authoring/audience_list_screen.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late ConfigStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_audience_list');
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    store = ConfigStore(database);
    await store.load();
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets(
    'returning from the audience editor does not throw',
    (tester) async {
      // _refreshHidden() (audience_list_screen.dart:27) is
      // `setState(() => _hidden = context.read<ConfigStore>().hiddenAudiences())`
      // — an assignment expression, so the closure evaluates to (and
      // "returns") the Future it just assigned. Flutter's setState() treats
      // a callback that returns a Future as a bug and throws
      // "setState() callback argument returned a Future.", which fires from
      // inside an assert() — so markNeedsBuild() is skipped too, meaning
      // the hidden-tones/audiences section silently never refreshes. This
      // test drives the exact real-world trigger: open an audience from the
      // list, then navigate back, same as _openEditor's
      // `await Navigator.push(...); _refreshHidden();`. The identical
      // pattern also exists in tone_list_screen.dart:28
      // (`_refreshHidden` for tones) — not covered separately since it's
      // the same bug in the same shape.
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ConfigStore>.value(
            value: store,
            child: const AudienceListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(store.audiences.first.label));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
