/// The backlog the store screenshots are taken of.
///
/// Rows in Amenbo's own shape, written by hand, in English — the one set of screenshots the stores
/// get, and the reason nothing is burned on top of them is that no language is written into the
/// picture. They are dated from the moment they are seeded rather than from literals, so a shot
/// taken a year from now still reads "18 minutes ago" instead of quietly aging into a stale one.
///
/// It is a demonstration backlog, not a copy of anybody's: the phone this is seeded onto is a
/// simulator, and a real backlog on a picture that goes to two stores is a leak with no way back.
library;

import 'store/backlog_store.dart';

/// Every row a screenshot needs, dated against [now].
List<BacklogChange> sampleBacklog(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  String at(Duration ago) => now.subtract(ago).toUtc().toIso8601String();
  String on(int days) =>
      day.add(Duration(days: days)).toIso8601String().split('T').first;

  return [
    BacklogChange.put('project', 4, _project(id: 4, name: 'wayfinder')),
    BacklogChange.put('project', 7, _project(id: 7, name: 'atlas')),

    // The task the detail shot opens. Everything a detail can show is on it: a body with sections,
    // a due date, an axis, a decision it rests on, and a timeline.
    BacklogChange.put(
      'task',
      312,
      _task(
        id: 312,
        projectId: 4,
        title: 'Keep the last search on the device',
        notes:
            '## What to do\n'
            '\n'
            '- Remember the words that were typed, not the rows they found\n'
            '- Five of them, newest first, dropped on erase\n'
            '- Show them under an empty field, and nowhere else\n'
            '\n'
            '## Why\n'
            '\n'
            'The same three or four words get typed every day, and typing them on a phone on a\n'
            'train is the slowest thing this app asks anybody to do.\n',
        status: 'todo',
        priority: 'high',
        assigneeKind: 'ai',
        dueOn: on(2),
        createdAt: at(const Duration(days: 2)),
        updatedAt: at(const Duration(minutes: 18)),
      ),
    ),
    BacklogChange.put(
      'task',
      309,
      _task(
        id: 309,
        projectId: 4,
        title: 'Rewrite the first-run copy',
        status: 'in_progress',
        priority: 'medium',
        createdAt: at(const Duration(days: 4)),
        updatedAt: at(const Duration(hours: 1)),
      ),
    ),
    BacklogChange.put(
      'task',
      305,
      _task(
        id: 305,
        projectId: 7,
        title: 'Sign the release with the new key',
        status: 'blocked',
        priority: 'high',
        assigneeKind: 'human',
        createdAt: at(const Duration(days: 5)),
        updatedAt: at(const Duration(hours: 3)),
      ),
    ),
    BacklogChange.put(
      'task',
      301,
      _task(
        id: 301,
        projectId: 4,
        title: 'Retry the uploads that time out',
        status: 'todo',
        priority: 'medium',
        assigneeKind: 'ai',
        createdAt: at(const Duration(days: 6)),
        updatedAt: at(const Duration(hours: 5)),
      ),
    ),
    BacklogChange.put(
      'task',
      298,
      _task(
        id: 298,
        projectId: 7,
        title: 'Measure cold start on a mid-range phone',
        status: 'todo',
        priority: 'medium',
        dueOn: on(-1),
        createdAt: at(const Duration(days: 8)),
        updatedAt: at(const Duration(days: 1)),
      ),
    ),
    BacklogChange.put(
      'task',
      296,
      _task(
        id: 296,
        projectId: 4,
        title: 'Drop the legacy export path',
        status: 'todo',
        priority: 'low',
        createdAt: at(const Duration(days: 9)),
        updatedAt: at(const Duration(days: 1, hours: 4)),
      ),
    ),
    BacklogChange.put(
      'task',
      292,
      _task(
        id: 292,
        projectId: 7,
        title: 'Name the four empty states',
        status: 'todo',
        priority: null,
        assigneeKind: 'ai',
        createdAt: at(const Duration(days: 11)),
        updatedAt: at(const Duration(days: 2)),
      ),
    ),
    BacklogChange.put(
      'task',
      288,
      _task(
        id: 288,
        projectId: 4,
        title: 'Split the settings sheet in two',
        status: 'done',
        priority: 'medium',
        createdAt: at(const Duration(days: 13)),
        updatedAt: at(const Duration(days: 1, hours: 2)),
        completedAt: at(const Duration(days: 1, hours: 2)),
      ),
    ),
    BacklogChange.put(
      'task',
      284,
      _task(
        id: 284,
        projectId: 7,
        title: 'Move the icons off the network',
        status: 'done',
        priority: 'low',
        createdAt: at(const Duration(days: 15)),
        updatedAt: at(const Duration(days: 2, hours: 6)),
        completedAt: at(const Duration(days: 2, hours: 6)),
      ),
    ),
    BacklogChange.put(
      'task',
      281,
      _task(
        id: 281,
        projectId: 4,
        title: 'Turn the crash reporter off by default',
        status: 'in_progress',
        priority: 'high',
        assigneeKind: 'human',
        createdAt: at(const Duration(days: 16)),
        updatedAt: at(const Duration(hours: 7)),
      ),
    ),
    BacklogChange.put(
      'task',
      277,
      _task(
        id: 277,
        projectId: 7,
        title: 'Write the migration note',
        status: 'todo',
        priority: 'medium',
        createdAt: at(const Duration(days: 18)),
        updatedAt: at(const Duration(days: 3)),
      ),
    ),

    BacklogChange.put(
      'task',
      274,
      _task(
        id: 274,
        projectId: 4,
        title: 'Read the backlog aloud in the right order',
        status: 'todo',
        priority: 'high',
        assigneeKind: 'ai',
        createdAt: at(const Duration(days: 19)),
        updatedAt: at(const Duration(days: 3, hours: 4)),
      ),
    ),
    BacklogChange.put(
      'task',
      271,
      _task(
        id: 271,
        projectId: 7,
        title: 'Stop the list jumping while it loads the next page',
        status: 'todo',
        priority: 'medium',
        dueOn: on(5),
        createdAt: at(const Duration(days: 21)),
        updatedAt: at(const Duration(days: 4)),
      ),
    ),
    BacklogChange.put(
      'task',
      268,
      _task(
        id: 268,
        projectId: 4,
        title: 'Give the empty search a way back to everything',
        status: 'todo',
        priority: 'low',
        createdAt: at(const Duration(days: 23)),
        updatedAt: at(const Duration(days: 5)),
      ),
    ),
    BacklogChange.put(
      'task',
      265,
      _task(
        id: 265,
        projectId: 7,
        title: 'Decide what a phone does with a record it cannot open',
        status: 'todo',
        priority: null,
        createdAt: at(const Duration(days: 26)),
        updatedAt: at(const Duration(days: 6)),
      ),
    ),

    // 301 is waiting on 305 — the hourglass on a row, and the line above the body on a detail.
    BacklogChange.put(
      'task_dependency',
      44,
      _dependency(id: 44, taskId: 301, blockedById: 305),
    ),

    BacklogChange.put(
      'task_comment',
      903,
      _comment(
        id: 903,
        taskId: 312,
        text:
            'Five is what fits under the field without pushing the results off '
            'the screen.',
        authorKind: 'human',
        createdAt: at(const Duration(days: 1, hours: 5)),
      ),
    ),
    BacklogChange.put(
      'task_comment',
      907,
      _comment(
        id: 907,
        taskId: 312,
        text:
            'Kept beside the cursor, not inside it — taking the copy again '
            'should not forget what somebody was looking for.',
        createdAt: at(const Duration(hours: 20)),
      ),
    ),
    BacklogChange.put(
      'task_comment',
      911,
      _comment(
        id: 911,
        taskId: 312,
        text: 'Erasing the phone\'s copy drops them too.',
        createdAt: at(const Duration(minutes: 18)),
      ),
    ),
    BacklogChange.put(
      'task_comment',
      898,
      _comment(
        id: 898,
        taskId: 309,
        text: 'Leading with "the PC has to be running Amenbo".',
        authorKind: 'human',
        createdAt: at(const Duration(hours: 1)),
      ),
    ),

    BacklogChange.put(
      'decision',
      91,
      _decision(
        id: 91,
        projectId: 4,
        title: 'The phone never writes back',
        body:
            'The phone reads the backlog and changes nothing in it.\n'
            '\n'
            '## Why\n'
            '\n'
            'Two writers over a place that is one file per record is a merge nobody asked for.\n',
        createdAt: at(const Duration(days: 21)),
        decidedAt: at(const Duration(days: 20)),
      ),
    ),
    BacklogChange.put(
      'decision',
      88,
      _decision(
        id: 88,
        projectId: 4,
        title: 'One key per person, one token per device',
        body: 'Losing a phone costs that phone its way in, and nothing else.\n',
        createdAt: at(const Duration(days: 24)),
        decidedAt: at(const Duration(days: 23)),
      ),
    ),
    BacklogChange.put(
      'decision',
      85,
      _decision(
        id: 85,
        projectId: 7,
        title: 'Ship without an account',
        body:
            'No sign-up, no server of ours. The place the rows come from is the '
            'owner\'s own.\n',
        draft: true,
        createdAt: at(const Duration(days: 3)),
      ),
    ),
    BacklogChange.put(
      'decision',
      79,
      _decision(
        id: 79,
        projectId: 4,
        title: 'Keep the search index on the device',
        body: 'Searching offline is most of what this app is for.\n',
        createdAt: at(const Duration(days: 30)),
        decidedAt: at(const Duration(days: 29)),
      ),
    ),
    BacklogChange.put(
      'decision',
      74,
      _decision(
        id: 74,
        projectId: 7,
        title: 'Two routes in, one shape out',
        body: 'A folder and a worker land the same rows in the same store.\n',
        createdAt: at(const Duration(days: 34)),
        decidedAt: at(const Duration(days: 33)),
      ),
    ),
    BacklogChange.put(
      'decision_comment',
      140,
      _decisionComment(
        id: 140,
        decisionId: 85,
        text: 'Nothing to sign in to is also nothing to be locked out of.',
        authorKind: 'human',
        createdAt: at(const Duration(days: 2)),
      ),
    ),
    BacklogChange.put(
      'decision_task_link',
      61,
      _decisionLink(id: 61, decisionId: 91, taskId: 312),
    ),

    BacklogChange.put(
      'dimension',
      12,
      _dimension(id: 12, projectId: 4, name: 'Area'),
    ),
    BacklogChange.put(
      'dimension_value',
      31,
      _dimensionValue(id: 31, dimensionId: 12, name: 'app'),
    ),
    BacklogChange.put(
      'dimension_value',
      32,
      _dimensionValue(id: 32, dimensionId: 12, name: 'plugin'),
    ),
    BacklogChange.put(
      'task_dimension_value',
      70,
      _taskDimensionValue(id: 70, taskId: 312, dimensionId: 12, valueId: 31),
    ),
  ];
}

/// The task the detail shot opens on.
const shotTaskId = 312;

Map<String, Object?> _project({required int id, required String name}) => {
  'id': id,
  'name': name,
  'slug': name,
  'notes': '',
  'color': null,
  'archived': 0,
  'default_view': 'board',
  'order_key': 'm',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _task({
  required int id,
  required int projectId,
  required String title,
  required String status,
  required String createdAt,
  required String updatedAt,
  String notes = '',
  String? priority,
  String? assigneeKind,
  String? dueOn,
  String? completedAt,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title,
  'notes': notes,
  'status': status,
  'priority': priority,
  'assignee_kind': assigneeKind,
  'draft': 0,
  'due_on': dueOn,
  'start_on': null,
  'created_at': createdAt,
  'updated_at': updatedAt,
  'status_changed_at': updatedAt,
  'completed_at': completedAt,
  'created_by_kind': 'human',
  'order_key': 'm',
  'subtype': 'default',
};

Map<String, Object?> _comment({
  required int id,
  required int taskId,
  required String text,
  required String createdAt,
  String authorKind = 'ai',
}) => {
  'id': id,
  'task_id': taskId,
  'text': text,
  'author_kind': authorKind,
  'created_at': createdAt,
  'updated_at': createdAt,
  'edited_at': null,
};

Map<String, Object?> _decision({
  required int id,
  required int projectId,
  required String title,
  required String body,
  required String createdAt,
  bool draft = false,
  String? decidedAt,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title,
  'body': body,
  'status': 'decided',
  'draft': draft ? 1 : 0,
  'created_at': createdAt,
  'updated_at': decidedAt ?? createdAt,
  'status_changed_at': decidedAt ?? createdAt,
  'decided_at': decidedAt,
  'decided_by': null,
};

Map<String, Object?> _decisionComment({
  required int id,
  required int decisionId,
  required String text,
  required String createdAt,
  String authorKind = 'ai',
}) => {
  'id': id,
  'decision_id': decisionId,
  'text': text,
  'author_kind': authorKind,
  'created_at': createdAt,
  'updated_at': createdAt,
  'edited_at': null,
};

Map<String, Object?> _dependency({
  required int id,
  required int taskId,
  required int blockedById,
}) => {
  'id': id,
  'task_id': taskId,
  'blocked_by_id': blockedById,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'established_at': '2026-01-01T00:00:00Z',
  'created_by_kind': 'human',
};

Map<String, Object?> _decisionLink({
  required int id,
  required int decisionId,
  required int taskId,
}) => {
  'id': id,
  'decision_id': decisionId,
  'task_id': taskId,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'linked_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _dimension({
  required int id,
  required int projectId,
  required String name,
}) => {
  'id': id,
  'project_id': projectId,
  'name': name,
  'role': 'none',
  'cardinality': 'single',
  'ordered': 0,
  'notes': '',
  'order_key': 'm',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _dimensionValue({
  required int id,
  required int dimensionId,
  required String name,
}) => {
  'id': id,
  'dimension_id': dimensionId,
  'name': name,
  'order_key': 'm',
  'start_on': null,
  'end_on': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _taskDimensionValue({
  required int id,
  required int taskId,
  required int dimensionId,
  required int valueId,
}) => {
  'id': id,
  'task_id': taskId,
  'dimension_id': dimensionId,
  'value_id': valueId,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};
