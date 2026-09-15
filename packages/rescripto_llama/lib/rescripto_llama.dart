/// On-device text generation over llama.cpp, for Android.
///
/// One model is loaded at a time and one generation runs at a time. The
/// native side runs every call on a single worker thread, so callers do not
/// need their own locking, but a second [LlamaEngine.generate] started while
/// one is still running waits behind it.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Sampling settings and the fully rendered prompt for one generation.
///
/// [prompt] is passed to the tokenizer as-is, with special tokens parsed, so
/// it should already carry the model family's chat markup.
class LlamaGenerationRequest {
  const LlamaGenerationRequest({
    required this.prompt,
    this.temperature = 0.7,
    this.topP = 0.95,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.maxTokens = 512,
    this.stopSequences = const [],
  });

  final String prompt;

  /// 0 or below selects greedy decoding.
  final double temperature;
  final double topP;
  final int topK;

  /// 1.0 disables the repetition penalty.
  final double repeatPenalty;
  final int maxTokens;

  /// Generation ends once the output contains any of these. The matched text
  /// may already have been streamed, so callers that must not show it should
  /// hold back a possible partial match themselves.
  final List<String> stopSequences;

  Map<String, Object?> toMap() => {
    'prompt': prompt,
    'temperature': temperature,
    'topP': topP,
    'topK': topK,
    'repeatPenalty': repeatPenalty,
    'maxTokens': maxTokens,
    'stopSequences': stopSequences,
  };
}

/// Entry point to the native engine. Use [instance].
class LlamaEngine {
  LlamaEngine._();

  static final LlamaEngine instance = LlamaEngine._();

  static const MethodChannel _channel = MethodChannel('rescripto_llama');

  final Map<int, StreamController<String>> _streams = {};
  int _nextId = 1;
  bool _handlerAttached = false;
  String? _modelPath;
  String? _lastLoadError;

  bool get isModelLoaded => _modelPath != null;

  /// Path of the loaded model, or null when none is loaded.
  String? get modelPath => _modelPath;

  /// Why the last [loadModel] call returned false, when the native side said.
  String? get lastLoadError => _lastLoadError;

  /// Loads the GGUF file at [path], replacing any model already loaded.
  ///
  /// Returns false with [lastLoadError] set when the model or its context
  /// could not be created. Throws [PlatformException] only for failures
  /// outside the load itself, such as the native library being missing.
  Future<bool> loadModel({
    required String path,
    required int threads,
    required int contextSize,
    int batchSize = 512,
  }) async {
    _attachHandler();
    final result = await _channel
        .invokeMapMethod<String, Object?>('loadModel', {
          'path': path,
          'threads': threads,
          'contextSize': contextSize,
          'batchSize': batchSize,
        });
    if (result?['ok'] == true) {
      _modelPath = path;
      _lastLoadError = null;
      return true;
    }
    _modelPath = null;
    final code = result?['code'] as String?;
    if (code == 'NATIVE_LIBRARY_UNAVAILABLE' ||
        code == 'CPU_BACKEND_UNAVAILABLE') {
      throw PlatformException(
        code: code!,
        message: result?['message'] as String?,
      );
    }
    _lastLoadError = result?['message'] as String?;
    return false;
  }

  /// Frees the loaded model and its context. Safe to call when nothing is
  /// loaded.
  Future<void> unloadModel() async {
    _attachHandler();
    await _channel.invokeMethod<void>('unloadModel');
    _modelPath = null;
  }

  /// Streams generated text for [request].
  ///
  /// Each event is new text only, never the accumulated output. Errors
  /// arrive as [PlatformException]. Cancelling the subscription stops the
  /// generation.
  Stream<String> generate(LlamaGenerationRequest request) {
    _attachHandler();
    final id = _nextId++;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        try {
          await _channel.invokeMethod<void>('generate', {
            'id': id,
            ...request.toMap(),
          });
        } on PlatformException catch (error) {
          if (_streams.remove(id) != null) {
            controller.addError(error);
            await controller.close();
          }
        }
      },
      onCancel: () async {
        // Still registered means the native side has not finished, so this
        // is a caller walking away mid-generation rather than normal
        // completion (which unregisters first).
        if (_streams.remove(id) != null) {
          await _channel.invokeMethod<void>('cancel', {'upToId': id});
        }
      },
    );
    _streams[id] = controller;
    return controller.stream;
  }

  /// Stops every generation started so far. A generation started after
  /// this call is not affected.
  Future<void> stopGeneration() async {
    _attachHandler();
    await _channel.invokeMethod<void>('cancel', {'upToId': _nextId - 1});
  }

  void _attachHandler() {
    if (_handlerAttached) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    _handlerAttached = true;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    final id = args['id'] as int?;
    if (id == null) return;
    switch (call.method) {
      case 'onText':
        _streams[id]?.add(args['text'] as String? ?? '');
      case 'onDone':
        await _streams.remove(id)?.close();
      case 'onError':
        final controller = _streams.remove(id);
        if (controller == null) return;
        controller.addError(
          PlatformException(
            code: args['code'] as String? ?? 'GENERATION_FAILED',
            message: args['message'] as String?,
          ),
        );
        await controller.close();
    }
  }
}
