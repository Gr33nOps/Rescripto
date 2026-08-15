part of 'package:flutter_whisper/flutter_whisper.dart';

/// Native availability reported before any voice-model download begins.
class WhisperNativeSupport {
  const WhisperNativeSupport({
    required this.supported,
    this.code,
    this.message,
  });

  final bool supported;
  final String? code;
  final String? message;

  factory WhisperNativeSupport.fromMap(Map<String, dynamic> map) =>
      WhisperNativeSupport(
        supported: map['supported'] == true,
        code: map['code'] as String?,
        message: map['message'] as String?,
      );
}

/// Abstract engine interface for platform implementations.
abstract class WhisperEngine {
  Future<WhisperNativeSupport> checkSupport();

  Future<void> initialize({
    required String modelPath,
    WhisperOptions? options,
  });

  /// Transcribes [audioPath]. [onProgress] receives 0..100.
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    WhisperOptions? options,
    void Function(int)? onProgress,
  });

  /// Starts mic recording to a WAV file.
  Future<void> startRecording();

  /// Stops mic recording; returns the recorded WAV path.
  Future<String> stopRecording();

  void cancel();

  Future<void> dispose();
}

/// Platform implementation using MethodChannel.
class MethodChannelWhisperEngine implements WhisperEngine {
  static const MethodChannel _channel = MethodChannel('flutter_whisper');

  void Function(int)? _onTranscribeProgress;

  MethodChannelWhisperEngine() {
    // Native progress events arrive as invocations on the same channel.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'transcribeProgress') {
        _onTranscribeProgress?.call(call.arguments as int);
      }
    });
  }

  @override
  Future<WhisperNativeSupport> checkSupport() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'checkSupport',
    );
    if (result == null) {
      return const WhisperNativeSupport(
        supported: false,
        code: 'NATIVE_CHECK_FAILED',
        message: 'Voice support could not be checked on this device.',
      );
    }
    return WhisperNativeSupport.fromMap(Map<String, dynamic>.from(result));
  }

  @override
  Future<void> initialize({
    required String modelPath,
    WhisperOptions? options,
  }) async {
    await _channel.invokeMethod('initialize', {
      'modelPath': modelPath,
      'options': options?.toMap(),
    });
  }

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    WhisperOptions? options,
    void Function(int)? onProgress,
  }) async {
    _onTranscribeProgress = onProgress;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'transcribeFile',
        {
          'audioPath': audioPath,
          'options': options?.toMap(),
        },
      );
      if (result == null) {
        throw WhisperError(
          'Native transcription returned no result.',
          WhisperErrorCode.transcriptionFailed,
        );
      }
      return TranscriptionResult.fromMap(Map<String, dynamic>.from(result));
    } finally {
      _onTranscribeProgress = null;
    }
  }

  @override
  Future<void> startRecording() async {
    await _channel.invokeMethod('startRecording');
  }

  @override
  Future<String> stopRecording() async {
    final path = await _channel.invokeMethod<String>('stopRecording');
    if (path == null || path.isEmpty) {
      throw WhisperError(
        'Native recorder returned no audio file.',
        WhisperErrorCode.transcriptionFailed,
      );
    }
    return path;
  }

  @override
  void cancel() {
    _channel.invokeMethod('cancel');
  }

  @override
  Future<void> dispose() async {
    _onTranscribeProgress = null;
    await _channel.invokeMethod('dispose');
  }
}
