import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_whisper/flutter_whisper.dart';

class _FakeEngine implements WhisperEngine {
  _FakeEngine(this.support, this.events);

  final WhisperNativeSupport support;
  final List<String> events;

  @override
  Future<WhisperNativeSupport> checkSupport() async {
    events.add('support');
    return support;
  }

  @override
  Future<void> initialize({
    required String modelPath,
    WhisperOptions? options,
  }) async {
    events.add('initialize:$modelPath');
  }

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async => '';

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    WhisperOptions? options,
    void Function(int)? onProgress,
  }) =>
      throw UnimplementedError();
}

void main() {
  test('parses complete native support diagnostics', () {
    final support = WhisperNativeSupport.fromMap({
      'supported': false,
      'code': 'NATIVE_LOAD_FAILED',
      'message': 'The voice library could not load.',
      'stage': 'whisper',
      'abis': ['arm64-v8a'],
      'apiLevel': 34,
      'libraryPath': '/data/app/lib/arm64',
      'detail': 'cannot locate symbol',
    });

    expect(support.supported, isFalse);
    expect(support.code, 'NATIVE_LOAD_FAILED');
    expect(support.stage, 'whisper');
    expect(support.abis, ['arm64-v8a']);
    expect(support.apiLevel, 34);
    expect(support.libraryPath, '/data/app/lib/arm64');
    expect(support.diagnosticMessage, contains('cannot locate symbol'));
  });

  test('runs support preflight before resolving a cached model', () async {
    final events = <String>[];
    final whisper = Whisper.withEngineForTesting(
      engine: _FakeEngine(
        const WhisperNativeSupport(supported: true),
        events,
      ),
      resolveModelPath: (model) async {
        events.add('cached-model');
        return '/cached/ggml-base.bin';
      },
    );

    await whisper.initialize(
      model: WhisperModel.base,
      downloadDirectory: '/cached',
    );

    expect(events, [
      'support',
      'cached-model',
      'initialize:/cached/ggml-base.bin',
    ]);
  });

  test('does not resolve or download a model when preflight fails', () async {
    final events = <String>[];
    final whisper = Whisper.withEngineForTesting(
      engine: _FakeEngine(
        const WhisperNativeSupport(
          supported: false,
          code: 'NATIVE_LOAD_FAILED',
          message: 'Native library failed.',
        ),
        events,
      ),
      resolveModelPath: (model) async {
        events.add('model');
        return '/unused';
      },
    );

    await expectLater(
      whisper.initialize(
        model: WhisperModel.base,
        downloadDirectory: '/unused',
      ),
      throwsA(
        isA<WhisperError>().having(
          (error) => error.nativeCode,
          'nativeCode',
          'NATIVE_LOAD_FAILED',
        ),
      ),
    );
    expect(events, ['support']);
  });
}
