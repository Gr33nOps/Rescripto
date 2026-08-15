import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WhisperContext JNI exports encode the underscore in flutter_whisper', () {
    final source = File(
      'third_party/flutter_whisper/android/src/main/cpp/whisper_jni.cpp',
    ).readAsStringSync();
    const prefix = 'Java_io_github_govindtank_flutter_1whisper_WhisperContext_';

    for (final method in [
      'nativeInit',
      'nativeTranscribe',
      'nativeCancel',
      'nativeFree',
    ]) {
      expect(source, contains('$prefix$method'));
    }
  });
}
