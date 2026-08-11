import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/provider_config.dart';
import 'provider_store.dart';

/// User-configured cloud providers, backed by SQLite via [ProviderStore].
///
/// Mirrors `ConfigStore` exactly: an in-memory cache kept in sync with the
/// database, [load] awaited before `runApp` alongside `configStore.load()`,
/// so nothing in the widget tree ever observes [isLoaded] false.
class ProviderRegistry extends ChangeNotifier {
  ProviderRegistry(this._store);

  final ProviderStore _store;

  List<ProviderConfig> _configs = const [];
  bool _isLoaded = false;

  List<ProviderConfig> get configs => List.unmodifiable(_configs);

  /// Only the providers a rewrite or speech request may actually pick.
  List<ProviderConfig> get enabledConfigs =>
      List.unmodifiable(_configs.where((c) => c.enabled));

  bool get isLoaded => _isLoaded;

  ProviderConfig? byId(String id) {
    for (final config in _configs) {
      if (config.id == id) return config;
    }
    return null;
  }

  Future<void> load() async {
    await _reload();
    _isLoaded = true;
  }

  /// A fresh id for a new config over [presetId]. Scoped to the preset
  /// rather than random alone, purely for readability in the credential
  /// index and debug logs — a user may configure the same preset more than
  /// once (two OpenAI accounts, two Ollama boxes), so [presetId] on its own
  /// is never unique.
  String newConfigId(String presetId) {
    final random = Random();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(36).toRadixString(36),
    ).join();
    return '$presetId-$suffix';
  }

  Future<void> save(ProviderConfig config) async {
    await _store.upsert(config);
    await _reload();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    await _reload();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final existing = byId(id);
    if (existing == null || existing.enabled == enabled) return;
    await save(existing.copyWith(enabled: enabled, updatedAt: DateTime.now()));
  }

  /// Disables every configured provider without touching a single
  /// credential — the emergency-wipe path removes secrets outright, this is
  /// for the lighter case of turning cloud access off without discarding
  /// keys the user will likely re-enable.
  ///
  /// One of the two things `panic_service.dart` documents as missing before
  /// Phase 2 — wired into `PanicService.wipeCredentials` in Step 5 alongside
  /// `ActiveRequestRegistry.cancelAll()`, the other half.
  Future<void> disableAll() async {
    var changed = false;
    for (final config in _configs) {
      if (config.enabled) {
        await _store.upsert(config.copyWith(enabled: false, updatedAt: DateTime.now()));
        changed = true;
      }
    }
    if (changed) await _reload();
  }

  Future<void> _reload() async {
    _configs = await _store.loadAll();
    notifyListeners();
  }
}
