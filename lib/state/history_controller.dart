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
    } catch (_) {
      _error = 'Couldn’t load your history. Try again.';
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
    } catch (_) {
      _error = 'Couldn’t delete that rewrite. Try again.';
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _error = null;
    try {
      await _storage.clearHistory();
      _entries = [];
    } catch (_) {
      _error = 'Couldn’t clear your history. Try again.';
    }
    notifyListeners();
  }
}
