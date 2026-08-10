import 'package:flutter/foundation.dart';

import '../models/history_entry.dart';
import '../services/storage_service.dart';

/// Rewrite history (stored only on-device).
class HistoryController extends ChangeNotifier {
  HistoryController(this._storage);

  /// Rows fetched per page.
  ///
  /// History was previously read in full on every visit to the tab, so someone
  /// with a long history paid for decoding all of it — and holding all of it —
  /// to look at the handful of entries that fit on screen.
  static const int pageSize = 50;

  final StorageService _storage;

  List<HistoryEntry> _entries = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  List<HistoryEntry> get entries => _entries;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  bool get isEmpty => _entries.isEmpty;
  String? get error => _error;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _storage.getHistory(limit: pageSize);
      _entries = page;
      _hasMore = page.length == pageSize;
    } catch (_) {
      _error = 'Couldn’t load your history. Try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Appends the next page. Safe to call repeatedly; overlapping calls and
  /// calls past the end of the table are ignored.
  Future<void> loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    _loadingMore = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _storage.getHistory(
        limit: pageSize,
        offset: _entries.length,
      );
      _entries = [..._entries, ...page];
      _hasMore = page.length == pageSize;
    } catch (_) {
      _error = 'Couldn’t load more history. Try again.';
    } finally {
      _loadingMore = false;
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
      _hasMore = false;
    } catch (_) {
      _error = 'Couldn’t clear your history. Try again.';
    }
    notifyListeners();
  }
}
