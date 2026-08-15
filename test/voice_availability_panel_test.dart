import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/state/speech_controller.dart';
import 'package:rescripto/widgets/mic_button.dart';

void main() {
  testWidgets('native failure shows details and a working retry action', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceAvailabilityPanel(
            availability: SpeechAvailability.retryableFailure,
            message: 'The voice library could not load at whisper.',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('Voice input could not start'), findsOneWidget);
    expect(find.textContaining('could not load'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('genuinely unsupported devices do not offer retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoiceAvailabilityPanel(
            availability: SpeechAvailability.unsupported,
            message: '64-bit ARM Android is required.',
          ),
        ),
      ),
    );

    expect(find.text('Voice input unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
