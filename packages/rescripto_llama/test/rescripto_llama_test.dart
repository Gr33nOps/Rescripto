import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto_llama/rescripto_llama.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rescripto_llama');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Map<String, Object?> loadReply;

  /// Delivers a call from "native" to the Dart handler, the way the Kotlin
  /// plugin does with channel.invokeMethod.
  Future<void> fromNative(String method, Map<String, Object?> args) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, args),
    );
    await messenger.handlePlatformMessage('rescripto_llama', data, (_) {});
  }

  setUp(() {
    calls.clear();
    loadReply = {'ok': true};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'loadModel') return loadReply;
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final engine = LlamaEngine.instance;

  group('loadModel', () {
    test('a successful load records the model path', () async {
      final ok = await engine.loadModel(
        path: '/models/a.gguf',
        threads: 4,
        contextSize: 2048,
      );
      expect(ok, isTrue);
      expect(engine.isModelLoaded, isTrue);
      expect(engine.modelPath, '/models/a.gguf');
      expect(calls.single.arguments, containsPair('contextSize', 2048));
    });

    test('a failed load returns false with the native reason', () async {
      loadReply = {
        'ok': false,
        'code': 'MODEL_LOAD_FAILED',
        'message': 'The model file could not be read as a GGUF model.',
      };
      final ok = await engine.loadModel(
        path: '/models/bad.gguf',
        threads: 4,
        contextSize: 2048,
      );
      expect(ok, isFalse);
      expect(engine.isModelLoaded, isFalse);
      expect(engine.lastLoadError, contains('GGUF'));
    });

    test(
      'a missing native library throws instead of looking like a bad file',
      () async {
        // LocalLlmService re-hashes the model file after a plain load failure.
        // A missing library must not send it down that path.
        loadReply = {
          'ok': false,
          'code': 'NATIVE_LIBRARY_UNAVAILABLE',
          'message': 'dlopen failed',
        };
        await expectLater(
          engine.loadModel(
            path: '/models/a.gguf',
            threads: 4,
            contextSize: 2048,
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'NATIVE_LIBRARY_UNAVAILABLE',
            ),
          ),
        );
      },
    );
  });

  group('generate', () {
    test('streams text in order and closes on done', () async {
      final received = <String>[];
      final done = Completer<void>();
      engine
          .generate(const LlamaGenerationRequest(prompt: 'hi'))
          .listen(received.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);

      final id = calls.last.arguments['id'] as int;
      expect(calls.last.method, 'generate');
      expect(calls.last.arguments, containsPair('prompt', 'hi'));

      await fromNative('onText', {'id': id, 'text': 'Hel'});
      await fromNative('onText', {'id': id, 'text': 'lo'});
      await fromNative('onDone', {'id': id});
      await done.future;

      expect(received, ['Hel', 'lo']);
      expect(
        calls.where((c) => c.method == 'cancel'),
        isEmpty,
        reason: 'a finished generation must not send a cancel',
      );
    });

    test('ignores text for another generation', () async {
      final received = <String>[];
      final done = Completer<void>();
      engine
          .generate(const LlamaGenerationRequest(prompt: 'hi'))
          .listen(received.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      final id = calls.last.arguments['id'] as int;

      await fromNative('onText', {'id': id + 100, 'text': 'stray'});
      await fromNative('onText', {'id': id, 'text': 'mine'});
      await fromNative('onDone', {'id': id});
      await done.future;

      expect(received, ['mine']);
    });

    test('a native error arrives as a PlatformException', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      engine
          .generate(const LlamaGenerationRequest(prompt: 'hi'))
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      final id = calls.last.arguments['id'] as int;

      await fromNative('onError', {
        'id': id,
        'code': 'CONTEXT_OVERFLOW',
        'message': 'The prompt uses 3000 of 2048 context tokens.',
      });
      await done.future;

      expect(
        errors.single,
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'CONTEXT_OVERFLOW',
        ),
      );
    });

    test(
      'cancelling the subscription cancels that generation natively',
      () async {
        final subscription = engine
            .generate(const LlamaGenerationRequest(prompt: 'hi'))
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);
        final id = calls.last.arguments['id'] as int;

        await subscription.cancel();

        final cancel = calls.lastWhere((c) => c.method == 'cancel');
        expect(cancel.arguments, {'upToId': id});
      },
    );
  });

  test('stopGeneration cancels everything started so far', () async {
    engine.generate(const LlamaGenerationRequest(prompt: 'a')).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final id = calls.last.arguments['id'] as int;

    await engine.stopGeneration();

    expect(calls.last.method, 'cancel');
    expect(calls.last.arguments, {'upToId': id});
  });
}
