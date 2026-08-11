import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_model.dart';
import 'local_llm_service.dart';
import 'network/network_exceptions.dart';

/// Streams [path] through SHA-256. Top-level so it can run under [compute].
Future<String> _sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

enum DownloadStatus { idle, downloading, verifying, completed, failed }

/// How often download progress is published to listeners, in milliseconds.
const int _progressIntervalMs = 250;

class DownloadProgress {
  const DownloadProgress({
    required this.modelId,
    required this.status,
    this.fraction = 0,
    this.receivedMb = 0,
    this.totalMb = 0,
    this.error,
    this.speedMbPerSec,
    this.eta,
  });

  final String modelId;
  final DownloadStatus status;
  final double fraction;
  final double receivedMb;
  final double totalMb;
  final String? error;

  /// Average throughput so far, or null before enough data to be meaningful.
  final double? speedMbPerSec;

  /// Rough time left at the current average speed.
  final Duration? eta;

  bool get isRunning =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.verifying;
}

/// Manages model catalog state, downloads and local files.
class ModelManager extends ChangeNotifier {
  ModelManager({Dio? dio}) : _dio = dio ?? Dio(), _ownsDio = dio == null {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  final Dio _dio;
  final bool _ownsDio;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DownloadProgress> _progress = {};
  String _activeModelId = '';

  List<AiModel> get catalog => ModelCatalog.models;

  DownloadProgress? progressFor(String modelId) => _progress[modelId];

  bool get hasActiveDownload => _activeModelId.isNotEmpty;
  String? get activeModelId => _activeModelId.isEmpty ? null : _activeModelId;

  Future<bool> isInstalled(AiModel model) async {
    final path = await LocalLlmService.filePathFor(model);
    return _verifyFile(File(path), model, verifyHash: false);
  }

  Future<Set<String>> installedIds() async {
    final installed = <String>{};
    for (final model in catalog) {
      if (await isInstalled(model)) installed.add(model.id);
    }
    return installed;
  }

  Future<void> download(AiModel model) async {
    if (_activeModelId.isNotEmpty) {
      _progress[model.id] = DownloadProgress(
        modelId: model.id,
        status: DownloadStatus.failed,
        error: 'Another model is already downloading.',
      );
      notifyListeners();
      return;
    }

    final path = await LocalLlmService.filePathFor(model);
    final destination = File(path);
    if (await _verifyFile(destination, model, verifyHash: false)) return;
    if (await destination.exists()) await destination.delete();
    final part = File('$path.part');

    _activeModelId = model.id;
    final cancelToken = CancelToken();
    _cancelTokens[model.id] = cancelToken;

    _progress[model.id] = DownloadProgress(
      modelId: model.id,
      status: DownloadStatus.downloading,
    );
    notifyListeners();

    try {
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > model.sizeBytes) {
        await part.delete();
        offset = 0;
      }

      final response = await _dio.get<ResponseBody>(
        model.downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
          validateStatus: (status) => status == 200 || status == 206,
        ),
      );
      if (response.data == null) {
        throw StateError('The model server returned no data.');
      }

      final resumed = offset > 0 && response.statusCode == 206;
      if (!resumed) offset = 0;
      final sink = part.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      var received = offset;
      final startedAt = offset;
      final clock = Stopwatch()..start();
      var lastNotifyMs = 0;
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;

          // Chunks arrive every few kilobytes. Rebuilding the models screen on
          // each one meant tens of thousands of layout passes over a 2 GB
          // download — enough UI work to visibly throttle the transfer itself.
          final elapsedMs = clock.elapsedMilliseconds;
          final done = received >= model.sizeBytes;
          if (!done && elapsedMs - lastNotifyMs < _progressIntervalMs) continue;
          lastNotifyMs = elapsedMs;

          final seconds = elapsedMs / 1000;
          final speed = seconds > 0.5
              ? (received - startedAt) / (1024 * 1024) / seconds
              : null;
          _progress[model.id] = DownloadProgress(
            modelId: model.id,
            status: DownloadStatus.downloading,
            fraction: (received / model.sizeBytes).clamp(0, 1),
            receivedMb: received / (1024 * 1024),
            totalMb: model.sizeBytes / (1024 * 1024),
            speedMbPerSec: speed,
            eta: speed != null && speed > 0
                ? Duration(
                    seconds:
                        ((model.sizeBytes - received) / (1024 * 1024) / speed)
                            .round(),
                  )
                : null,
          );
          notifyListeners();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      _progress[model.id] = DownloadProgress(
        modelId: model.id,
        status: DownloadStatus.verifying,
        fraction: 1,
        receivedMb: model.sizeBytes / (1024 * 1024),
        totalMb: model.sizeBytes / (1024 * 1024),
      );
      notifyListeners();

      if (!await _verifyFile(part, model, verifyHash: true)) {
        await _deleteFile(part.path);
        throw StateError(
          'Downloaded file failed its size, format, or checksum verification.',
        );
      }
      await part.rename(path);

      _progress[model.id] = DownloadProgress(
        modelId: model.id,
        status: DownloadStatus.completed,
        fraction: 1,
        receivedMb: _fileSizeMb(path),
        totalMb: _fileSizeMb(path),
      );
    } on DioException catch (e) {
      if (cancelToken.isCancelled) {
        _progress[model.id] = DownloadProgress(
          modelId: model.id,
          status: DownloadStatus.idle,
        );
      } else {
        _progress[model.id] = DownloadProgress(
          modelId: model.id,
          status: DownloadStatus.failed,
          error: _downloadError(e),
        );
      }
    } catch (e) {
      _progress[model.id] = DownloadProgress(
        modelId: model.id,
        status: DownloadStatus.failed,
        error: _downloadError(e),
      );
    } finally {
      _cancelTokens.remove(model.id);
      _activeModelId = '';
      notifyListeners();
    }
  }

  String _downloadError(Object error) {
    if (error is DioException) {
      if (error.error is NetworkBlockedByPolicyException) {
        // A deliberate block, not a network fault — the connectivity message
        // below would send someone chasing a problem that doesn't exist.
        final reason = (error.error as NetworkBlockedByPolicyException).reason;
        return reason == NetworkBlockReason.killSwitch
            ? 'Network access is turned off. Turn it back on in Settings to '
                  'download this model.'
            : 'Model downloads are turned off in Settings.';
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return 'Download timed out. Check your connection and try again.';
        case DioExceptionType.connectionError:
          return 'Couldn’t connect. Check your internet connection and try again.';
        case DioExceptionType.badCertificate:
          return 'A secure connection couldn’t be established. Try again later.';
        case DioExceptionType.badResponse:
          return 'This model file is unavailable right now. Try again later.';
        case DioExceptionType.cancel:
          return 'Download cancelled.';
        case DioExceptionType.unknown:
          break;
      }
    }

    final text = error.toString().toLowerCase();
    if (text.contains('space') || text.contains('storage')) {
      return 'Not enough storage. Free some space and try again.';
    }
    if (text.contains('checksum') || text.contains('verification')) {
      return 'The downloaded file couldn’t be verified. Try downloading it again.';
    }
    return 'Download failed. Check your connection and try again.';
  }

  Future<void> cancelDownload(AiModel model) async {
    final token = _cancelTokens[model.id];
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
  }

  Future<void> deleteModel(AiModel model) async {
    final path = await LocalLlmService.filePathFor(model);
    await _deleteFile(path);
    await _deleteFile('$path.part');
    _progress.remove(model.id);
    notifyListeners();
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  double _fileSizeMb(String path) {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() / (1024 * 1024) : 0;
  }

  Future<bool> _verifyFile(
    File file,
    AiModel model, {
    required bool verifyHash,
  }) async {
    if (!await file.exists() || await file.length() != model.sizeBytes) {
      return false;
    }
    final magic = await file
        .openRead(0, 4)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (!listEquals(magic, const [0x47, 0x47, 0x55, 0x46])) return false;
    if (!verifyHash) return true;
    // Hashing a 2 GB file is tens of seconds of solid CPU. On the UI isolate
    // that lands as a full app freeze the moment the progress bar hits 100%.
    final digest = await compute(_sha256OfFile, file.path);
    return digest == model.sha256;
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel('Model manager disposed');
    }
    if (_ownsDio) _dio.close(force: true);
    super.dispose();
  }
}
