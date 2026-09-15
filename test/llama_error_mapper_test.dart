import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/local/llama_error_mapper.dart';

void main() {
  const mapper = LlamaErrorMapper();

  test('keeps CPU backend failures distinct from corrupt model text', () {
    final mapped = mapper.map(
      PlatformException(
        code: 'CPU_BACKEND_UNAVAILABLE',
        message: 'No compatible llama.cpp CPU backend could be loaded.',
      ),
    );

    expect(mapped, isA<ModelLoadFailedException>());
    final failure = mapped as ModelLoadFailedException;
    expect(failure.nativeReason, contains('CPU backend'));
    expect(failure.nativeReason, isNot(contains('GGUF')));
  });

  test('a missing native library is a load failure with its reason', () {
    final mapped = mapper.map(
      PlatformException(
        code: 'NATIVE_LIBRARY_UNAVAILABLE',
        message: 'dlopen failed: library "libllama.so" not found',
      ),
    );

    expect(mapped, isA<ModelLoadFailedException>());
    expect(
      (mapped as ModelLoadFailedException).nativeReason,
      contains('libllama.so'),
    );
  });

  test('a prompt longer than the context maps to ContextOverflowException', () {
    final mapped = mapper.map(
      PlatformException(
        code: 'CONTEXT_OVERFLOW',
        message: 'The prompt uses 2100 of 2048 context tokens.',
      ),
    );

    expect(mapped, isA<ContextOverflowException>());
  });
}
