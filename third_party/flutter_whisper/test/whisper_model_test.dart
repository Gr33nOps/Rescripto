import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_whisper/flutter_whisper.dart';

void main() {
  test('published model metadata is complete and checksum-shaped', () {
    for (final model in WhisperModel.values) {
      expect(model.fileSizeBytes, greaterThan(0));
      expect(model.fileSizeHuman, isNotEmpty);
      expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(model.downloadUrl, startsWith('https://huggingface.co/'));
    }
  });

  test('large model resolves to the available large-v3 artifact', () {
    expect(WhisperModel.large.downloadUrl, contains('ggml-large-v3.bin'));
  });

  test('catalog files are the multilingual variants', () {
    expect(
        WhisperModel.values,
        everyElement(predicate<WhisperModel>(
          (model) => model.isMultilingual,
        )));
  });
}
