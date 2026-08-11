import 'package:sqflite/sqflite.dart';

import '../../models/workflow_definition.dart';
import '../../models/workflow_step.dart';
import '../db/app_database.dart';

/// Raw SQLite persistence for [WorkflowDefinition]. Mirrors
/// `ProviderStore`'s shape: `WorkflowRegistry` is the in-memory,
/// `ChangeNotifier` cache the rest of the app reads from; this is what it
/// persists through.
class WorkflowStore {
  WorkflowStore(this._database);

  final AppDatabase _database;

  Future<List<WorkflowDefinition>> loadAll() async {
    final db = await _database.db;
    final rows = await db.query('workflow', orderBy: 'created_at');
    final workflows = <WorkflowDefinition>[];
    for (final row in rows) {
      final steps = await _loadSteps(db, row['id'] as String);
      workflows.add(
        WorkflowDefinition(
          id: row['id'] as String,
          name: row['name'] as String,
          steps: steps,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
        ),
      );
    }
    return workflows;
  }

  Future<void> upsert(WorkflowDefinition workflow) async {
    final db = await _database.db;
    await db.insert('workflow', {
      'id': workflow.id,
      'name': workflow.name,
      'created_at': workflow.createdAt.toIso8601String(),
      'updated_at': workflow.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _replaceSteps(db, workflow.id, workflow.steps);
  }

  Future<void> delete(String id) async {
    final db = await _database.db;
    // workflow_step rows cascade via the foreign key AppDatabase.openAt
    // already turns on.
    await db.delete('workflow', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WorkflowStep>> _loadSteps(DatabaseExecutor db, String workflowId) async {
    final rows = await db.query(
      'workflow_step',
      where: 'workflow_id = ?',
      whereArgs: [workflowId],
      orderBy: 'sort_order',
    );
    return rows.map(WorkflowStep.fromMap).toList();
  }

  Future<void> _replaceSteps(
    DatabaseExecutor db,
    String workflowId,
    List<WorkflowStep> steps,
  ) async {
    final batch = db.batch();
    batch.delete('workflow_step', where: 'workflow_id = ?', whereArgs: [workflowId]);
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      batch.insert('workflow_step', {
        ...step.toMap(),
        'workflow_id': workflowId,
        'sort_order': i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
