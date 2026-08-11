import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/workflow_definition.dart';
import 'workflow_store.dart';

/// User-created workflows, backed by SQLite via [WorkflowStore]. Mirrors
/// `ProviderRegistry`'s shape exactly: an in-memory cache kept in sync with
/// the database.
class WorkflowRegistry extends ChangeNotifier {
  WorkflowRegistry(this._store);

  final WorkflowStore _store;

  List<WorkflowDefinition> _workflows = const [];
  bool _isLoaded = false;

  List<WorkflowDefinition> get workflows => List.unmodifiable(_workflows);
  bool get isLoaded => _isLoaded;

  WorkflowDefinition? byId(String id) {
    for (final workflow in _workflows) {
      if (workflow.id == id) return workflow;
    }
    return null;
  }

  Future<void> load() async {
    await _reload();
    _isLoaded = true;
  }

  String newId() {
    final random = Random();
    final suffix = List.generate(8, (_) => random.nextInt(36).toRadixString(36)).join();
    return 'workflow_$suffix';
  }

  String newStepId() {
    final random = Random();
    final suffix = List.generate(8, (_) => random.nextInt(36).toRadixString(36)).join();
    return 'step_$suffix';
  }

  Future<void> save(WorkflowDefinition workflow) async {
    await _store.upsert(workflow);
    await _reload();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    await _reload();
  }

  Future<void> _reload() async {
    _workflows = await _store.loadAll();
    notifyListeners();
  }
}
