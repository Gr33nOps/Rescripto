import 'package:flutter/foundation.dart';

import '../models/history_entry.dart';
import '../services/storage_service.dart';

/// Rewrite history (stored only on-device).
class HistoryController extends ChangeNotifier {
  HistoryController(this._storage);

  final StorageService _storage;

  List<HistoryEntry> _entries = [];
  bool _loading = true;

  List<HistoryEntry> get entries => _entries;
  bool get loading => _loading;
  bool get isEmpty => _entries.isEmpty;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    _entries = await _storage.getHistory();
    _loading = false;
    notifyListeners();
  }

  Future<void> delete(int id) async {
    await _storage.deleteHistory(id);
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.clearHistory();
    _entries = [];
    notifyListeners();
  }
}
