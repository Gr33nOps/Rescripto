import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/rewrite_result.dart';
import 'package:rescripto/widgets/result_view.dart';

const _request = RewriteRequest(
  sourceText: 'Original',
  toneId: 'professional',
  intensity: RewriteIntensity.moderate,
  length: RewriteLength.same,
);

RewriteResult _result(int outputCount) => RewriteResult(
  request: _request,
  outputs: [
    for (var index = 0; index < outputCount; index++)
      RewriteOutput(text: 'Rewrite ${index + 1}'),
  ],
);

Widget _host(RewriteResult result, {double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: ResultView(result: result)),
    ),
  );
}

void main() {
  testWidgets(
    'normalizes selected variant when a new result has fewer outputs',
    (tester) async {
      await tester.pumpWidget(_host(_result(3)));
      await tester.tap(find.text('V3'));
      await tester.pump();

      await tester.pumpWidget(_host(_result(1)));
      await tester.pump();

      expect(find.text('Rewrite 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('handles an empty output list without indexing it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_result(0)));

    expect(find.text('No rewrite output was produced.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wraps result controls on a narrow large-text viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(_result(3), textScale: 2));

    expect(find.text('Result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
