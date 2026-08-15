import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WhisperContext JNI exports encode the underscore in flutter_whisper',
    () {
      final source = File(
        'third_party/flutter_whisper/android/src/main/cpp/whisper_jni.cpp',
      ).readAsStringSync();
      const prefix =
          'Java_io_github_govindtank_flutter_1whisper_WhisperContext_';

      for (final method in [
        'nativeInit',
        'nativeTranscribe',
        'nativeCancel',
        'nativeFree',
      ]) {
        expect(source, contains('$prefix$method'));
      }
    },
  );

  test('Whisper initializes on the CPU-only compatibility path', () {
    final source = File(
      'third_party/flutter_whisper/android/src/main/cpp/whisper_jni.cpp',
    ).readAsStringSync();

    expect(source, contains('cparams.use_gpu = false;'));
    expect(source, contains('cparams.flash_attn = false;'));
    expect(source, contains('catch (const std::bad_alloc&)'));
  });

  test('release shrinking preserves the JNI callback name', () {
    final gradle = File(
      'third_party/flutter_whisper/android/build.gradle',
    ).readAsStringSync();
    final rules = File(
      'third_party/flutter_whisper/android/consumer-rules.pro',
    ).readAsStringSync();

    expect(gradle, contains('consumerProguardFiles "consumer-rules.pro"'));
    expect(
      rules,
      contains('io.github.govindtank.flutter_whisper.WhisperContext'),
    );
  });

  test('recorded PCM16 WAV uses the direct Android decoder first', () {
    final source = File(
      'third_party/flutter_whisper/android/src/main/cpp/whisper_jni.cpp',
    ).readAsStringSync();

    expect(source, contains('load_pcm16_wav_16k_mono'));
    expect(
      source.indexOf('if (load_pcm16_wav_16k_mono(path, out)) return true;'),
      lessThan(source.indexOf('ma_decoder_init_file')),
    );
    expect(source, contains('audio_format != 1'));
    expect(source, contains('sample_rate != 16000'));
    expect(source, contains('bits_per_sample != 16'));
  });
}
