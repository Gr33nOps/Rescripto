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
}
