import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_whisper/flutter_whisper.dart';
import 'package:rescripto/state/speech_controller.dart';

void main() {
  group('speechAvailabilityForError', () {
    test('treats an unsupported ABI as permanent', () {
      final error = WhisperError(
        '64-bit ARM is required.',
        WhisperErrorCode.nativeUnavailable,
        nativeCode: 'ABI_UNSUPPORTED',
      );

      expect(speechAvailabilityForError(error), SpeechAvailability.unsupported);
    });

    test('treats native load and JNI failures as retryable', () {
      for (final code in [
        'NATIVE_LOAD_FAILED',
        'NATIVE_CHECK_FAILED',
        'JNI_SMOKE_TEST_FAILED',
      ]) {
        expect(
          speechAvailabilityForError(PlatformException(code: code)),
          SpeechAvailability.retryableFailure,
          reason: code,
        );
      }
    });

    test('does not disable voice for unrelated errors containing support', () {
      expect(
        speechAvailabilityForError(Exception('support server timed out')),
        SpeechAvailability.available,
      );
    });
  });
}
