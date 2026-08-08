import 'package:flutter/foundation.dart';

import '../models/history_entry.dart';
import '../services/storage_service.dart';

/// Rewrite history (stored only on-device).
class HistoryController extends ChangeNotifier {
  HistoryController(this._storage);

  final StorageService _storage;

  List<HistoryEntry> _entries = [];
  bool _loading = true;
  String? _error;

  List<HistoryEntry> get entries => _entries;
  bool get loading => _loading;
  bool get isEmpty => _entries.isEmpty;
  String? get error => _error;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _entries = await _storage.getHistory();
    } catch (e) {
      _error = 'Could not load rewrite history: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> delete(int id) async {
    _error = null;
    try {
      await _storage.deleteHistory(id);
      _entries.removeWhere((e) => e.id == id);
    } catch (e) {
      _error = 'Could not delete that history item: $e';
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _error = null;
    try {
      await _storage.clearHistory();
      _entries = [];
    } catch (e) {
      _error = 'Could not clear rewrite history: $e';
    }
    notifyListeners();
  }
}
