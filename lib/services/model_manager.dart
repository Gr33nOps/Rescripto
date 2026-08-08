import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_model.dart';
import 'local_llm_service.dart';

enum DownloadStatus { idle, downloading, completed, failed }

class DownloadProgress {
  const DownloadProgress({
    required this.modelId,
    required this.status,
    this.fraction = 0,
    this.receivedMb = 0,
    this.totalMb = 0,
    this.error,
  });

  final String modelId;
  final DownloadStatus status;
  final double fraction;
  final double receivedMb;
  final double totalMb;
  final String? error;

  bool get isRunning => status == DownloadStatus.downloading;
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
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          _progress[model.id] = DownloadProgress(
            modelId: model.id,
            status: DownloadStatus.downloading,
            fraction: (received / model.sizeBytes).clamp(0, 1),
            receivedMb: received / (1024 * 1024),
            totalMb: model.sizeBytes / (1024 * 1024),
          );
          notifyListeners();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

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
          error: e.message,
        );
      }
    } catch (e) {
      _progress[model.id] = DownloadProgress(
        modelId: model.id,
        status: DownloadStatus.failed,
        error: e.toString(),
      );
    } finally {
      _cancelTokens.remove(model.id);
      _activeModelId = '';
      notifyListeners();
    }
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
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == model.sha256;
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
