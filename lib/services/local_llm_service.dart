import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../engine/engine_exception.dart';
import '../engine/generation_options.dart';
import '../engine/local/stop_sequence_emitter.dart';
import '../models/ai_model.dart';
import '../models/rewrite_output.dart';

/// Wraps the native llama.cpp engine (via flutter_llama).
///
/// Handles model loading, generation and unloading. All inference is
/// on-device. Owned exclusively by `LocalEngineHost`
/// (`lib/engine/local/local_engine_host.dart`), which serialises access to
/// the singleton native engine underneath — nothing here does that itself.
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
  ///
  /// Throws [ModelNotInstalledException] if the file isn't on disk, or
  /// [ModelLoadFailedException] if the engine rejected it — typed at the
  /// point each is actually known, rather than as a generic message a caller
  /// downstream has to pattern-match to find out which one happened.
  Future<void> loadModel(
    AiModel model, {
    required int threads,
    required int contextSize,
    required bool useGpu,
  }) async {
    final path = await filePathFor(model);
    if (!File(path).existsSync()) {
      throw ModelNotInstalledException(model.id);
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
      // 999 is llama.cpp's "offload every layer". -1 silently offloads nothing.
      nGpuLayers: useGpu ? 999 : 0,
      contextSize: contextSize,
      batchSize: 512,
      useGpu: useGpu,
      verbose: false,
    );

    final ok = await _llama.loadModel(config);
    if (!ok) {
      // A load failure on a file that exists (the only thing checked above)
      // can mean the file is corrupted rather than the engine being at
      // fault — see ModelCorruptedException's doc for why that can happen
      // silently. Re-hash here, once, only in response to this actual
      // failure — never proactively, and never on every launch.
      if (!await _isCorrupted(path, model)) {
        throw ModelLoadFailedException(_llama.lastLoadError);
      }
      await File(path).delete();
      throw ModelCorruptedException(model.id);
    }
    _loadedConfig = requested;
  }

  /// True if [path] fails a full hash check against [model]'s known-good
  /// SHA-256. A read failure (the file vanished, a permissions error) is
  /// treated as "not corrupted" here — [ModelLoadFailedException] is the
  /// more honest report for a file this method could not even examine.
  Future<bool> _isCorrupted(String path, AiModel model) async {
    try {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString() != model.sha256;
    } catch (_) {
      return false;
    }
  }

  /// Context size to actually use: the user's setting, never larger than what
  /// the model was trained for (the native side clamps again as a backstop).
  static int effectiveContextSize(AiModel model, int requested) {
    return math.min(requested, model.contextSize);
  }

  /// Unloads the current model and frees memory.
  Future<void> unloadModel() async {
    if (isModelLoaded) {
      await _llama.unloadModel();
    }
    _loadedConfig = null;
  }

  /// Generates a single rewrite output.
  ///
  /// [onDelta], if given, is called with *new* text only — never the
  /// accumulated string. Stop-sequence detection has to withhold the tail of
  /// the buffer that might still turn into a marker (a marker can arrive
  /// split across native tokens), so the actual hold-back arithmetic lives in
  /// [StopSequenceEmitter], which — unlike this class — doesn't wrap a
  /// platform channel and can be unit-tested directly.
  Future<RewriteOutput> generate(
    String prompt, {
    required GenerationOptions options,
    void Function(String delta)? onDelta,
  }) async {
    final activeContext = _loadedConfig?.contextSize;
    if (activeContext == null) {
      throw const ModelLoadFailedException('No model is currently loaded.');
    }
    final estimatedPromptTokens = (utf8.encode(prompt).length / 3).ceil();
    final availableOutputTokens = activeContext - estimatedPromptTokens;
    if (availableOutputTokens < 64) {
      throw ContextOverflowException(
        promptTokens: estimatedPromptTokens,
        contextSize: activeContext,
      );
    }
    final boundedMaxTokens = math.min(
      options.maxOutputTokens,
      availableOutputTokens,
    );
    final params = GenerationParams(
      prompt: prompt,
      temperature: options.temperature,
      topP: options.topP,
      topK: options.topK,
      maxTokens: boundedMaxTokens,
      repeatPenalty: options.repeatPenalty,
      stopSequences: options.stopSequences,
    );

    final emitter = StopSequenceEmitter(options.stopSequences);
    final stopwatch = Stopwatch()..start();

    await for (final token in _llama.generateStream(params)) {
      final delta = emitter.append(token);
      if (delta.isNotEmpty) onDelta?.call(delta);
      // The native side already stops on these sequences; this is a safety
      // net for stray trailing text, so ending the loop here just skips
      // processing tokens we already know we would discard.
      if (emitter.isStopped) break;
    }
    stopwatch.stop();

    final (:text, :finalDelta) = emitter.finish();
    if (finalDelta.isNotEmpty) onDelta?.call(finalDelta);

    return RewriteOutput(text: text, generationTimeMs: stopwatch.elapsedMilliseconds);
  }

  /// Stops any in-flight generation.
  Future<void> stopGeneration() async {
    await _llama.stopGeneration();
  }

  Future<void> dispose() => unloadModel();
}
