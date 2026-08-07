import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ai_model.dart';
import '../services/model_manager.dart';
import '../services/settings_service.dart';

/// Drives the model catalog screen: install, select, delete models.
class ModelsController extends ChangeNotifier {
  ModelsController({required this._manager, required this._settings}) {
    _load();
  }

  final ModelManager _manager;
  final SettingsService _settings;

  final Set<String> _installed = {};
  bool _scanning = true;

  List<AiModel> get catalog => ModelCatalog.models;
  Set<String> get installed => Set.unmodifiable(_installed);
  bool get scanning => _scanning;

  String get selectedModelId => _settings.selectedModelId;

  bool isInstalled(String id) => _installed.contains(id);

  DownloadProgress? progressFor(String id) => _manager.progressFor(id);

  Future<void> _load() async {
    _scanning = true;
    notifyListeners();
    _installed.clear();
    _installed.addAll(await _manager.installedIds());
    _scanning = false;
    notifyListeners();
  }

  Future<void> selectModel(AiModel model) async {
    await _settings.setSelectedModelId(model.id);
    notifyListeners();
  }

  Future<void> download(AiModel model) async {
    await _manager.download(model);
    await _refreshInstalled();
  }

  Future<void> cancelDownload(AiModel model) async {
    await _manager.cancelDownload(model);
  }

  Future<void> deleteModel(AiModel model) async {
    await _manager.deleteModel(model);
    await _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    _installed
      ..clear()
      ..addAll(await _manager.installedIds());
    notifyListeners();
  }
}
