import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/speech_service.dart';

void main() {
  test('local transcription treats Whisper silence markers as empty audio', () {
    expect(normalizeLocalTranscript('[ Silence ] [ Silence ]'), isEmpty);
    expect(normalizeLocalTranscript(' [silence]\n[ Silence ] '), isEmpty);
    expect(normalizeLocalTranscript('Please send the report.'),
        'Please send the report.');
  });
}
