import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_llama/flutter_llama.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import '../models/rewrite_output.dart';

/// Wraps the native llama.cpp engine (via flutter_llama).
///
/// Handles model loading, generation and unloading. All inference is on-device.
class LocalLlmService {
  final FlutterLlama _llama = FlutterLlama.instance;
  ({String path, int threads, int contextSize, bool useGpu})? _loadedConfig;

  bool get isModelLoaded => _llama.isModelLoaded;

  String? get loadedModelPath => _llama.modelPath;

  /// Absolute path where downloaded GGUF models are stored.
  static Future<String> modelsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, AppConstants.modelsDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Absolute file path for a catalog model (whether installed or not).
  static Future<String> filePathFor(AiModel model) async {
    final dir = await modelsDirectory();
    return p.join(dir, model.localFileName);
  }

  /// Loads a GGUF model into memory.
  Future<void> loadModel(
    AiModel model, {
    required int threads,
    required int contextSize,
    required bool useGpu,
  }) async {
    final path = await filePathFor(model);
    if (!File(path).existsSync()) {
      throw StateError('Model file not found: $path');
    }
    final requested = (
      path: path,
      threads: threads,
      contextSize: contextSize,
      useGpu: useGpu,
    );
    if (isModelLoaded && _loadedConfig == requested) return;

    if (isModelLoaded) {
      await unloadModel();
    }

    final config = LlamaConfig(
      modelPath: path,
      nThreads: threads,
      nGpuLayers: useGpu ? -1 : 0,
      contextSize: contextSize,
      batchSize: 512,
      useGpu: useGpu,
      verbose: false,
    );

    final ok = await _llama.loadModel(config);
    if (!ok) {
      throw StateError('Failed to load model "${model.name}".');
    }
    _loadedConfig = requested;
  }

  /// Unloads the current model and frees memory.
  Future<void> unloadModel() async {
    if (isModelLoaded) {
      await _llama.unloadModel();
    }
    _loadedConfig = null;
  }

  /// Generates a single rewrite output.
  Future<RewriteOutput> generate(
    String prompt, {
    double temperature = 0.5,
    int maxTokens = AppConstants.defaultMaxTokens,
    void Function(String partial)? onToken,
  }) async {
    final activeContext = _loadedConfig?.contextSize;
    if (activeContext == null) {
      throw StateError('Model configuration is unavailable. Reload the model.');
    }
    final estimatedPromptTokens = (utf8.encode(prompt).length / 3).ceil();
    final availableOutputTokens = activeContext - estimatedPromptTokens;
    if (availableOutputTokens < 64) {
      throw StateError(
        'The input is too long for the $activeContext-token context. '
        'Shorten it or increase Context size in Settings.',
      );
    }
    final boundedMaxTokens = math.min(maxTokens, availableOutputTokens);
    final params = GenerationParams(
      prompt: prompt,
      temperature: temperature,
      topP: 0.95,
      topK: 40,
      maxTokens: boundedMaxTokens,
      repeatPenalty: 1.1,
      stopSequences: const ['<|eot_id|>', '<|end_of_turn|>', '<|im_end|>'],
    );

    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    await for (final token in _llama.generateStream(params)) {
      buffer.write(token);
      final partial = _trimStopSequence(
        buffer.toString(),
        params.stopSequences,
      );
      onToken?.call(partial);
    }
    stopwatch.stop();
    final text = _trimStopSequence(buffer.toString(), params.stopSequences);
    return RewriteOutput(
      text: text,
      generationTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Stops any in-flight generation.
  Future<void> stopGeneration() async {
    await _llama.stopGeneration();
  }

  String _trimStopSequence(String text, List<String> stopSequences) {
    var end = text.length;
    for (final sequence in stopSequences) {
      final index = text.indexOf(sequence);
      if (index >= 0 && index < end) end = index;
    }
    return text.substring(0, end);
  }

  Future<void> dispose() => unloadModel();
}
