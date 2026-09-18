// The reading half: which state a task is read under, how big a window is, where a count stops,
// and that a search is answered by the index rather than by walking the backlog.

import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';

/// Every test reads the same day, so a list drawn here and a count taken beside it cannot
/// disagree about which tasks are late.
final today = DateTime(2026, 8, 9);

void main() {
  late BacklogStore store;

  setUp(() => store = BacklogStore.openInMemory());
  tearDown(() => store.close());

  group('the four states', () {
    test("a state is Amenbo's status, whatever else is true of the row", () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, status: 'in_progress')),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, status: 'in_progress', draft: 1),
        ),
        BacklogChange.put('task', 3, task(id: 3)),
      ]);

      expect(
        store.inState(TaskState.inProgress, today: today).map((row) => row.id),
        [1, 2],
      );
      expect(store.stateCount(TaskState.inProgress, today: today).value, 2);
    });

    test('what is waiting on something stays in todo, and says what for', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('task', 2, task(id: 2, status: 'blocked')),
        BacklogChange.put('task', 3, task(id: 3, draft: 1)),
        BacklogChange.put('task', 4, task(id: 4, startOn: '2026-09-01')),
        // Waiting on 1, which is not finished.
        BacklogChange.put('task', 5, task(id: 5)),
        BacklogChange.put(
          'task_dependency',
          1,
          dependency(id: 1, taskId: 5, blockedById: 1),
        ),
        // Waiting on a decision nobody has ruled on.
        BacklogChange.put('task', 6, task(id: 6)),
        BacklogChange.put('decision', 7, decision(id: 7)),
        BacklogChange.put(
          'decision_task_link',
          1,
          decisionLink(id: 1, decisionId: 7, taskId: 6),
        ),
      ]);

      // Only Amenbo's own `blocked` is a state of its own. The rest are waiting, and waiting
      // is something a row says about itself.
      final todo = store.inState(TaskState.todo, today: today);
      expect(todo.map((row) => row.id), [1, 3, 4, 5, 6]);
      expect(
        store.inState(TaskState.blocked, today: today).map((row) => row.id),
        [2],
      );

      final byId = {for (final row in todo) row.id: row};
      expect(
        byId[5]!.blockedBy,
        1,
        reason: 'the screen writes the blocker out by number',
      );
      expect(byId[6]!.undecided, 7);
      expect(byId[3]!.draft, isTrue);
      expect(byId[4]!.startOn, '2026-09-01');
    });

    test(
      'a settled blocker and a settled decision stop holding a task back',
      () {
        store.applyPage([
          BacklogChange.put('task', 1, task(id: 1, status: 'done')),
          BacklogChange.put('task', 5, task(id: 5)),
          BacklogChange.put(
            'task_dependency',
            1,
            dependency(id: 1, taskId: 5, blockedById: 1),
          ),
          BacklogChange.put('decision', 7, decision(id: 7, draft: false)),
          BacklogChange.put(
            'decision_task_link',
            1,
            decisionLink(id: 1, decisionId: 7, taskId: 5),
          ),
        ]);

        expect(store.inState(TaskState.blocked, today: today), isEmpty);
        expect(
          store.inState(TaskState.todo, today: today).map((row) => row.id),
          [5],
        );
      },
    );

    test('todo puts the late first, then today, then priority', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, priority: 'high')),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, priority: 'low', dueOn: '2026-08-07'),
        ),
        BacklogChange.put(
          'task',
          3,
          task(id: 3, priority: 'low', dueOn: '2026-08-09'),
        ),
        BacklogChange.put('task', 4, task(id: 4, priority: null)),
        BacklogChange.put('task', 5, task(id: 5, priority: 'medium')),
      ]);

      expect(store.inState(TaskState.todo, today: today).map((row) => row.id), [
        2,
        3,
        1,
        5,
        4,
      ]);
    });

    test('finished is all of it, newest first', () {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, status: 'done', completedAt: '2026-08-08T10:00:00Z'),
        ),
        BacklogChange.put(
          'task',
          2,
          task(
            id: 2,
            status: 'rejected',
            statusChangedAt: '2026-08-05T10:00:00Z',
          ),
        ),
        BacklogChange.put(
          'task',
          3,
          task(id: 3, status: 'done', completedAt: '2026-07-01T10:00:00Z'),
        ),
      ]);

      // The one closed last summer is as much a part of it as the one closed yesterday: the
      // device holds the whole copy, so nothing is left out for being old.
      expect(
        store.inState(TaskState.finished, today: today).map((row) => row.id),
        [1, 2, 3],
      );
    });

    test('a long-closed one is still handed back, one window at a time', () {
      store.applyPage([
        for (var id = 1; id <= Windows.list + 5; id++)
          BacklogChange.put(
            'task',
            id,
            task(id: id, status: 'done', completedAt: '2024-01-01T10:00:00Z'),
          ),
      ]);

      expect(
        store.inState(TaskState.finished, today: today),
        hasLength(Windows.list),
      );
      // The count is asked the same question as the window, or the number on the switch would be
      // counting something the list is not.
      expect(
        store.stateCount(TaskState.finished, today: today).value,
        Windows.list + 5,
      );
    });

    test('the next window carries on where the last one stopped', () {
      store.applyPage([
        for (var id = 1; id <= Windows.list + 5; id++)
          BacklogChange.put('task', id, task(id: id)),
      ]);

      final first = store.inState(TaskState.todo, today: today);
      final next = store.inState(
        TaskState.todo,
        today: today,
        offset: first.length,
      );
      expect(first, hasLength(Windows.list));
      expect(next, hasLength(5));
      expect({
        ...first.map((row) => row.id),
        ...next.map((row) => row.id),
      }, hasLength(Windows.list + 5));
    });
  });

  group('counting', () {
    test('a count stops at the cap instead of walking the backlog', () {
      store.applyPage([
        for (var id = 1; id <= Counted.cap + 5; id++)
          BacklogChange.put('task', id, task(id: id)),
      ]);

      final total = store.stateCount(TaskState.todo, today: today);
      expect(total.value, Counted.cap);
      expect(total.overflowed, isTrue);
    });
  });

  group('the one list face', () {
    setUp(() {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'QR に載せるものを決める', status: 'done'),
        ),
        BacklogChange.put('task', 2, task(id: 2, title: 'QR の読み取りを実装する')),
        BacklogChange.put(
          'task',
          3,
          task(id: 3, title: 'ペアリングの案内を書く', notes: 'QR を読んでペアリングする'),
        ),
        BacklogChange.put(
          'task',
          4,
          task(id: 4, title: '署名鍵を用意する', updatedAt: '2026-08-09T09:00:00Z'),
        ),
        BacklogChange.put('dimension', 1, dimension(id: 1)),
        BacklogChange.put(
          'dimension_value',
          1,
          dimensionValue(id: 1, dimensionId: 1),
        ),
        BacklogChange.put(
          'task_dimension_value',
          1,
          taskDimensionValue(id: 1, taskId: 4, dimensionId: 1, valueId: 1),
        ),
      ]);
    });

    test(
      'a search finds the word wherever it is written, closed tasks included',
      () {
        final hits = store.tasks(const TaskQuery(text: 'ペアリング'));

        expect(hits.map((row) => row.id), contains(3));
        expect(hits.single.excerpt, isNotEmpty);
      },
    );

    test('a task matching in more than one place comes back once', () {
      store.applyPage([
        BacklogChange.put(
          'task',
          5,
          task(id: 5, title: 'めずらしい語', notes: 'めずらしい語をもう一度'),
        ),
      ]);

      final hits = store.tasks(const TaskQuery(text: 'めずらしい語'));
      expect(hits.map((row) => row.id), [5]);
    });

    test('a query too short for the index is still answered', () {
      // Two characters cannot be a trigram, and `qr` is exactly the sort of thing people type.
      final hits = store.tasks(const TaskQuery(text: 'QR'));
      expect(hits.map((row) => row.id), containsAll([1, 2, 3]));
    });

    test('a category value narrows the same face', () {
      expect(store.tasks(const TaskQuery(valueId: 1)).map((row) => row.id), [
        4,
      ]);
    });

    test('a narrowing and a search can be asked for together', () {
      // Three tasks say "QR" and one of them wears the value, so the two together answer with
      // neither set on its own.
      expect(store.tasks(const TaskQuery(text: 'QR')).map((row) => row.id), [
        3,
        2,
        1,
      ]);
      expect(
        store
            .tasks(const TaskQuery(text: 'ペアリング', valueId: 1))
            .map((row) => row.id),
        isEmpty,
      );
    });

    test('every project on the machine arrives, and one can be picked out', () {
      store.applyPage([
        BacklogChange.put('task', 9, task(id: 9, projectId: 42)),
        BacklogChange.put('project', 16, project(id: 16)),
        BacklogChange.put('project', 42, project(id: 42, name: 'nsys')),
      ]);

      expect(store.tasks(const TaskQuery(projectId: 42)).map((row) => row.id), [
        9,
      ]);
      expect(store.projects().map((row) => row.name), ['amenbo', 'nsys']);
    });
  });

  group('decisions', () {
    test(
      'an empty query lists them newest first, linked to anything or not',
      () {
        store.applyPage([
          BacklogChange.put(
            'decision',
            1,
            decision(id: 1, createdAt: '2026-08-01T00:00:00Z'),
          ),
          BacklogChange.put(
            'decision',
            2,
            decision(id: 2, createdAt: '2026-08-05T00:00:00Z'),
          ),
        ]);

        expect(store.decisions().map((row) => row.id), [2, 1]);
        expect(store.decisionCount().value, 2);
      },
    );

    test('a search reaches their bodies and their comments', () {
      store.applyPage([
        BacklogChange.put(
          'decision',
          1,
          decision(id: 1, body: 'XChaCha20 を選ぶ'),
        ),
        BacklogChange.put('decision', 2, decision(id: 2)),
        BacklogChange.put('decision_comment', 1, {
          'id': 1,
          'decision_id': 2,
          'text': 'XChaCha20 のほうが nonce が長い',
          'author_kind': 'ai',
          'created_at': '2026-08-02T00:00:00Z',
          'updated_at': '2026-08-02T00:00:00Z',
          'edited_at': null,
        }),
      ]);

      expect(store.decisions(text: 'XChaCha20').map((row) => row.id), [2, 1]);
    });
  });

  group('a task detail', () {
    test('comments open on the newest few and walk backwards', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        for (var id = 1; id <= 10; id++)
          BacklogChange.put(
            'task_comment',
            id,
            comment(
              id: id,
              taskId: 1,
              text: 'こめんと $id',
              createdAt: '2026-08-0${id % 9 + 1}T00:00:0${id % 10}Z',
            ),
          ),
      ]);

      final opening = store.comments(1);
      expect(opening, hasLength(Windows.comments));
      // A conversation is read forwards even when the window is taken off the end.
      expect(
        opening.first.createdAt.compareTo(opening.last.createdAt),
        lessThanOrEqualTo(0),
      );

      final older = store.comments(
        1,
        limit: Windows.commentPage,
        before: opening.first.id,
      );
      expect(older.map((row) => row.id), isNot(contains(opening.first.id)));
      expect(store.commentCount(1).value, 10);
    });

    test(
      'both directions of a dependency come back with the other side state',
      () {
        store.applyPage([
          BacklogChange.put('task', 1, task(id: 1, status: 'done')),
          BacklogChange.put('task', 2, task(id: 2)),
          BacklogChange.put(
            'task_dependency',
            1,
            dependency(id: 1, taskId: 2, blockedById: 1),
          ),
        ]);

        expect(store.blockers(2).single.status, 'done');
        expect(store.blocking(1).single.id, 2);
      },
    );

    test('chips, commits and attachments come off the same task', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('dimension', 1, dimension(id: 1)),
        BacklogChange.put(
          'dimension_value',
          1,
          dimensionValue(id: 1, dimensionId: 1),
        ),
        BacklogChange.put(
          'task_dimension_value',
          1,
          taskDimensionValue(id: 1, taskId: 1, dimensionId: 1, valueId: 1),
        ),
        BacklogChange.put('task_commit', 1, taskCommit(id: 1, taskId: 1)),
        BacklogChange.put('attachment', 1, attachment(id: 1, targetId: 1)),
      ]);

      expect(store.chips(1).single.value, 'app');
      expect(store.commits(1), hasLength(1));
      // The bytes stay on the PC; the row is what says the file is there at all.
      expect(store.attachments('task', 1).single.filename, 'shot.png');
    });

    test('a decision and the tasks it governs reach each other', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('decision', 7, decision(id: 7)),
        BacklogChange.put(
          'decision_task_link',
          1,
          decisionLink(id: 1, decisionId: 7, taskId: 1),
        ),
        BacklogChange.put('decision', 8, decision(id: 8)),
        BacklogChange.put('decision_edge', 1, {
          'id': 1,
          'decision_id': 8,
          'target_decision_id': 7,
          'kind': 'builds_on',
          'created_at': '2026-08-01T00:00:00Z',
          'updated_at': '2026-08-01T00:00:00Z',
          'drawn_at': '2026-08-01T00:00:00Z',
        }),
      ]);

      expect(store.decisionsFor(1).single.id, 7);
      expect(store.tasksFor(7).single.id, 1);
      expect(store.edgesFor(8).single.kind, 'builds_on');
    });
  });

  group('every project on the machine, narrowed rather than divided', () {
    test('a bundle stacks the projects together, and can hold one', () {
      store.applyPage([
        BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
        BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
        BacklogChange.put(
          'task',
          1,
          task(id: 1, projectId: 16, status: 'in_progress'),
        ),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, projectId: 20, status: 'in_progress'),
        ),
      ]);

      expect(store.inState(TaskState.inProgress, today: today), hasLength(2));
      expect(
        store
            .inState(TaskState.inProgress, today: today, projectId: 20)
            .single
            .id,
        2,
      );
      expect(store.projects().map((row) => row.name), ['viewer', 'nsys']);
    });

    test('an archived project is off the front screen and still searchable', () {
      store.applyPage([
        BacklogChange.put('project', 16, project(id: 16)),
        BacklogChange.put(
          'project',
          20,
          project(id: 20, name: 'old', archived: 1),
        ),
        BacklogChange.put('task', 1, task(id: 1, projectId: 16, title: 'qr')),
        BacklogChange.put('task', 2, task(id: 2, projectId: 20, title: 'qr')),
      ]);

      expect(store.inState(TaskState.todo, today: today).single.id, 1);
      // Remembering how something ended up is what an archived project is kept for.
      expect(store.tasks(const TaskQuery(text: 'qr')).map((row) => row.id), [
        2,
        1,
      ]);
      // It is not offered as somewhere to narrow to either.
      expect(store.projects().map((row) => row.id), [16]);
    });

    test('a task whose project has not arrived yet is not hidden', () {
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);
      expect(store.inState(TaskState.todo, today: today), hasLength(1));
    });
  });

  group('what arrived while the screen was being read', () {
    test('it is counted against the PC\'s clock, not the phone\'s', () {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, updatedAt: '2026-08-09T09:00:00Z'),
        ),
      ]);
      final drawn = store.latestTaskChange();
      expect(drawn, '2026-08-09T09:00:00Z');
      expect(store.movedSince(drawn).value, 0);

      store.applyPage([
        BacklogChange.put(
          'task',
          2,
          task(id: 2, updatedAt: '2026-08-09T09:05:00Z'),
        ),
        BacklogChange.put(
          'task',
          1,
          task(id: 1, updatedAt: '2026-08-09T09:06:00Z'),
        ),
      ]);
      expect(store.movedSince(drawn).value, 2);
    });

    test('a screen that drew nothing counts everything as new', () {
      expect(store.latestTaskChange(), isNull);
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);
      expect(store.movedSince(null).value, 1);
    });

    test('it counts only the project being looked at', () {
      store.applyPage([
        BacklogChange.put('project', 16, project(id: 16)),
        BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
        BacklogChange.put(
          'task',
          1,
          task(id: 1, projectId: 20, updatedAt: '2026-08-09T09:05:00Z'),
        ),
      ]);
      expect(store.movedSince(null, projectId: 16).value, 0);
      expect(store.movedSince(null, projectId: 20).value, 1);
    });
  });
}
