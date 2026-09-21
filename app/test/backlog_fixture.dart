// Rows in Amenbo's own shape, written by hand.
//
// The columns are the ones `amenbo sync snapshot` puts in `tables`; the defaults here are what a
// freshly filed task looks like. Tests override only the column they are about, so what a test is
// checking stays legible next to what it merely needs to exist.

import 'package:amenbo_viewer/ui/refs.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row in a list, found by the whole of the first line it is drawn with.
///
/// Every list puts the number in front of the title, in the same text, so a title on its own
/// matches nothing — see `RowSurface`.
Finder taskRowTitled(int id, String title, {bool skipOffstage = true}) =>
    find.text('${taskRef(id)} $title', skipOffstage: skipOffstage);

Finder decisionRowTitled(int id, String title) =>
    find.text('${decisionRef(id)} $title');

Map<String, Object?> task({
  required int id,
  int projectId = 16,
  String title = 'タスク',
  String notes = '',
  String status = 'todo',
  String? priority = 'medium',
  String? assigneeKind,
  int draft = 0,
  String? dueOn,
  String? startOn,
  String createdAt = '2026-08-01T00:00:00Z',
  String updatedAt = '2026-08-01T00:00:00Z',
  String? statusChangedAt,
  String? completedAt,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title,
  'notes': notes,
  'status': status,
  'priority': priority,
  'assignee_kind': assigneeKind,
  'draft': draft,
  'due_on': dueOn,
  'start_on': startOn,
  'created_at': createdAt,
  'updated_at': updatedAt,
  'status_changed_at': statusChangedAt ?? createdAt,
  'completed_at': completedAt,
  'created_by_kind': 'ai',
  'order_key': 'm',
  'subtype': 'default',
};

Map<String, Object?> comment({
  required int id,
  required int taskId,
  String text = 'こめんと',
  String authorKind = 'ai',
  String createdAt = '2026-08-01T00:00:00Z',
}) => {
  'id': id,
  'task_id': taskId,
  'text': text,
  'author_kind': authorKind,
  'created_at': createdAt,
  'updated_at': createdAt,
  'edited_at': null,
};

Map<String, Object?> decision({
  required int id,
  int projectId = 16,
  String title = '決定',
  String body = '',
  String status = 'decided',
  bool draft = true,
  String createdAt = '2026-08-01T00:00:00Z',
  String? decidedAt,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title,
  'body': body,
  // Decided from the moment it is saved, so the default is the one that varies: the writing,
  // which starts unfinished and is lowered by finishing it.
  'status': status,
  'draft': draft ? 1 : 0,
  'created_at': createdAt,
  'updated_at': createdAt,
  'status_changed_at': createdAt,
  'decided_at': decidedAt,
  'decided_by': null,
};

Map<String, Object?> decisionComment({
  required int id,
  required int decisionId,
  String text = 'こめんと',
  String authorKind = 'ai',
  String createdAt = '2026-08-01T00:00:00Z',
}) => {
  'id': id,
  'decision_id': decisionId,
  'text': text,
  'author_kind': authorKind,
  'created_at': createdAt,
  'updated_at': createdAt,
  'edited_at': null,
};

Map<String, Object?> decisionEdge({
  required int id,
  required int decisionId,
  required int targetDecisionId,
  String kind = 'builds_on',
}) => {
  'id': id,
  'decision_id': decisionId,
  'target_decision_id': targetDecisionId,
  'kind': kind,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
  'created_by_kind': 'ai',
};

Map<String, Object?> dependency({
  required int id,
  required int taskId,
  required int blockedById,
}) => {
  'id': id,
  'task_id': taskId,
  'blocked_by_id': blockedById,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
  'established_at': '2026-08-01T00:00:00Z',
  'created_by_kind': 'ai',
};

Map<String, Object?> decisionLink({
  required int id,
  required int decisionId,
  required int taskId,
}) => {
  'id': id,
  'decision_id': decisionId,
  'task_id': taskId,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
  'linked_at': '2026-08-01T00:00:00Z',
};

Map<String, Object?> dimension({required int id, String name = 'Area'}) => {
  'id': id,
  'project_id': 16,
  'name': name,
  'role': 'none',
  'cardinality': 'single',
  'ordered': 0,
  'notes': '',
  'order_key': 'm',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
};

Map<String, Object?> dimensionValue({
  required int id,
  required int dimensionId,
  String name = 'app',
}) => {
  'id': id,
  'dimension_id': dimensionId,
  'name': name,
  'order_key': 'm',
  'start_on': null,
  'end_on': null,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
};

Map<String, Object?> taskDimensionValue({
  required int id,
  required int taskId,
  required int dimensionId,
  required int valueId,
}) => {
  'id': id,
  'task_id': taskId,
  'dimension_id': dimensionId,
  'value_id': valueId,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
};

Map<String, Object?> attachment({
  required int id,
  required int targetId,
  String targetType = 'task',
  String filename = 'shot.png',
  int sizeBytes = 1024,
}) => {
  'id': id,
  'target_type': targetType,
  'target_id': targetId,
  'filename': filename,
  'size_bytes': sizeBytes,
  'kind': 'blob',
  'mime': 'image/png',
  'blob_hash':
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  'url': null,
  'order_key': 'm',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
  'created_by_kind': 'ai',
};

Map<String, Object?> taskCommit({
  required int id,
  required int taskId,
  String sha = '0000000000000000000000000000000000000000',
}) => {
  'id': id,
  'task_id': taskId,
  'sha': sha,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
  'created_by_kind': 'ai',
};

Map<String, Object?> project({
  required int id,
  String name = 'amenbo',
  int archived = 0,
}) => {
  'id': id,
  'name': name,
  'slug': name,
  'notes': '',
  'color': null,
  'archived': archived,
  'default_view': 'board',
  'order_key': 'm',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
};
