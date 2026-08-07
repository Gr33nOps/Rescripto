import 'dart:async';
import 'dart:io';

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
  ModelManager({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  final Dio _dio;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DownloadProgress> _progress = {};
  String _activeModelId = '';

  List<AiModel> get catalog => ModelCatalog.models;

  DownloadProgress? progressFor(String modelId) => _progress[modelId];

  bool get hasActiveDownload => _activeModelId.isNotEmpty;

  Future<bool> isInstalled(AiModel model) async {
    final path = await LocalLlmService.filePathFor(model);
    return File(path).existsSync();
  }

  Future<Set<String>> installedIds() async {
    final installed = <String>{};
    for (final model in catalog) {
      if (await isInstalled(model)) installed.add(model.id);
    }
    return installed;
  }

  Future<void> download(AiModel model) async {
    if (_activeModelId.isNotEmpty) return;

    final path = await LocalLlmService.filePathFor(model);
    if (File(path).existsSync()) return;

    _activeModelId = model.id;
    final cancelToken = CancelToken();
    _cancelTokens[model.id] = cancelToken;

    _progress[model.id] = DownloadProgress(
      modelId: model.id,
      status: DownloadStatus.downloading,
    );
    notifyListeners();

    try {
      await _dio.download(
        model.downloadUrl,
        path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final totalBytes = total > 0 ? total : received;
          _progress[model.id] = DownloadProgress(
            modelId: model.id,
            status: DownloadStatus.downloading,
            fraction: totalBytes > 0 ? received / totalBytes : 0,
            receivedMb: received / (1024 * 1024),
            totalMb: totalBytes / (1024 * 1024),
          );
          notifyListeners();
        },
      );

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
        await _deleteFile(path);
      } else {
        _progress[model.id] = DownloadProgress(
          modelId: model.id,
          status: DownloadStatus.failed,
          error: e.message,
        );
      }
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
}
