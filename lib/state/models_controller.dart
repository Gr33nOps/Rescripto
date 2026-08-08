import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ai_model.dart';
import '../services/local_llm_service.dart';
import '../services/model_manager.dart';
import '../services/settings_service.dart';

/// Drives the model catalog screen: install, select, delete models.
class ModelsController extends ChangeNotifier {
  ModelsController({
    required this._manager,
    required this._settings,
    required this._llm,
  }) {
    _manager.addListener(_onManagerChanged);
    _load();
  }

  final ModelManager _manager;
  final SettingsService _settings;
  final LocalLlmService _llm;

  final Set<String> _installed = {};
  bool _scanning = true;
  String? _error;

  List<AiModel> get catalog => ModelCatalog.models;
  Set<String> get installed => Set.unmodifiable(_installed);
  bool get scanning => _scanning;
  String? get error => _error;
  bool get hasActiveDownload => _manager.hasActiveDownload;
  String? get activeDownloadId => _manager.activeModelId;

  String get selectedModelId => _settings.selectedModelId;

  bool isInstalled(String id) => _installed.contains(id);

  DownloadProgress? progressFor(String id) => _manager.progressFor(id);

  Future<void> _load() async {
    _scanning = true;
    _error = null;
    notifyListeners();
    try {
      _installed
        ..clear()
        ..addAll(await _manager.installedIds());
    } catch (_) {
      _error =
          'Couldn’t check installed models. Restart the app and try again.';
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> selectModel(AiModel model) async {
    await _settings.setSelectedModelId(model.id);
    notifyListeners();
  }

  Future<void> download(AiModel model) async {
    _error = null;
    await _manager.download(model);
    await _refreshInstalled();
  }

  Future<void> cancelDownload(AiModel model) async {
    await _manager.cancelDownload(model);
  }

  Future<void> deleteModel(AiModel model) async {
    final modelPath = await LocalLlmService.filePathFor(model);
    if (selectedModelId == model.id || _llm.loadedModelPath == modelPath) {
      await _llm.unloadModel();
    }
    await _manager.deleteModel(model);
    await _refreshInstalled();
    if (selectedModelId == model.id) {
      final installedModels = catalog.where(
        (candidate) => _installed.contains(candidate.id),
      );
      final fallback = installedModels.isEmpty ? null : installedModels.first;
      await _settings.setSelectedModelId(
        fallback?.id ?? ModelCatalog.defaultModel.id,
      );
      notifyListeners();
    }
  }

  Future<void> _refreshInstalled() async {
    _installed
      ..clear()
      ..addAll(await _manager.installedIds());
    notifyListeners();
  }

  void _onManagerChanged() => notifyListeners();

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    super.dispose();
  }
}
