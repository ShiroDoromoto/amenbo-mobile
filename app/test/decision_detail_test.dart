// The decision face: the same skeleton as a task's, with the one thing a decision has instead of
// a deadline — whether anybody has answered it, and what is not moving until they do.

import 'package:amenbo_viewer/decision_detail.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/ui/marks.dart';
import 'package:amenbo_viewer/ui/refs.dart';
import 'package:amenbo_viewer/ui/task_row.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';
import 'words_fixture.dart';

final today = DateTime(2026, 8, 9, 12);

void main() {
  late BacklogStore store;
  late List<int> openedTasks;
  late List<int> openedDecisions;
  late List<String> shared;

  setUp(() {
    store = BacklogStore.openInMemory();
    openedTasks = [];
    openedDecisions = [];
    shared = [];
  });
  tearDown(() => store.close());

  Widget face({int id = 31, String? project, void Function(int)? onProject}) =>
      MaterialApp(
        localizationsDelegates: Words.localizationsDelegates,
        supportedLocales: Words.supportedLocales,
        theme: viewerTheme(Brightness.light),
        home: DecisionDetailScreen(
          store: store,
          decisionId: id,
          projectName: project,
          onProject: onProject,
          onOpenTask: openedTasks.add,
          onOpenDecision: openedDecisions.add,
          onShare: (text) async => shared.add(text),
          clock: () => today,
        ),
      );

  testWidgets('the number, the project and the title lead', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 31, decision(id: 31, title: 'きめた')),
    ]);

    await tester.pumpWidget(
      face(project: 'viewer', onProject: openedTasks.add),
    );

    expect(find.text(decisionRef(31)), findsOneWidget);
    expect(find.text('きめた'), findsOneWidget);

    await tester.tap(find.text('viewer'));
    expect(openedTasks, [16]);
  });

  group('the half-written one is why this screen exists', () {
    testWidgets('it says it is unfinished, and how much is held by it', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('decision', 31, decision(id: 31)),
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('task', 2, task(id: 2, status: 'done')),
        BacklogChange.put(
          'decision_task_link',
          1,
          decisionLink(id: 1, decisionId: 31, taskId: 1),
        ),
        BacklogChange.put(
          'decision_task_link',
          2,
          decisionLink(id: 2, decisionId: 31, taskId: 2),
        ),
      ]);

      await tester.pumpWidget(face());

      // One of the two: work already finished was not held up by it.
      expect(find.textContaining(words.stallDraft), findsOneWidget);
      expect(find.textContaining(words.decisionHeld(1)), findsOneWidget);
    });

    testWidgets('a settled one says nothing about being unfinished', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put(
          'decision',
          31,
          decision(id: 31, draft: false, decidedAt: '2026-08-02T00:00:00Z'),
        ),
      ]);

      await tester.pumpWidget(face());

      expect(find.text(words.stallDraft), findsNothing);
      expect(
        find.textContaining(decisionStatusWords(words, 'decided')),
        findsWidgets,
      );
    });
  });

  testWidgets('what it stands on is named and can be opened', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 31, decision(id: 31)),
      BacklogChange.put('decision', 12, decision(id: 12, title: 'もとの')),
      BacklogChange.put(
        'decision_edge',
        1,
        decisionEdge(id: 1, decisionId: 31, targetDecisionId: 12),
      ),
    ]);

    await tester.pumpWidget(face());

    expect(find.text(edgeWords(words, 'builds_on')), findsOneWidget);
    await tester.tap(find.text('もとの'));
    expect(openedDecisions, [12]);
  });

  testWidgets('the work it produced is the way back out', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 31, decision(id: 31)),
      BacklogChange.put('task', 7, task(id: 7, title: 'つくる')),
      BacklogChange.put(
        'decision_task_link',
        1,
        decisionLink(id: 1, decisionId: 31, taskId: 7),
      ),
    ]);

    await tester.pumpWidget(face());

    expect(find.byType(TaskRow), findsOneWidget);
    await tester.tap(taskRowTitled(7, 'つくる'));
    expect(openedTasks, [7]);
  });

  testWidgets('its timeline is read forwards, newest last', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 31, decision(id: 31)),
      for (var id = 1; id <= 3; id++)
        BacklogChange.put(
          'decision_comment',
          id,
          decisionComment(
            id: id,
            decisionId: 31,
            text: 'こめんと$id',
            createdAt: '2026-08-0${id}T00:00:00Z',
          ),
        ),
    ]);

    await tester.pumpWidget(face());

    final first = tester.getTopLeft(find.text('こめんと1')).dy;
    final last = tester.getTopLeft(find.text('こめんと3')).dy;
    expect(first, lessThan(last));
  });

  testWidgets('three lines leave: the number, the title, where it stands', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put(
        'decision',
        31,
        decision(id: 31, title: 'きめた', body: 'ながいほんぶん'),
      ),
    ]);

    await tester.pumpWidget(face());
    await tester.tap(find.byTooltip(words.share));

    expect(shared, ['${decisionRef(31)}\nきめた\nDraft']);
  });

  testWidgets(
    'a decision the phone does not hold says so instead of breaking',
    (tester) async {
      await tester.pumpWidget(face(id: 4242));

      expect(find.text(words.decisionGone), findsOneWidget);
      expect(find.byTooltip(words.share), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nothing overflows at the largest text a phone offers', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put(
        'decision',
        31,
        decision(
          id: 31,
          title:
              'a decision title long enough that it runs past one line before '
              'anybody turns their text up',
          body: '## なぜ\n\n- ひとつ\n- ふたつ\n',
        ),
      ),
      BacklogChange.put('task', 7, task(id: 7)),
      BacklogChange.put(
        'decision_task_link',
        1,
        decisionLink(id: 1, decisionId: 31, taskId: 7),
      ),
      BacklogChange.put(
        'decision_comment',
        1,
        decisionComment(id: 1, decisionId: 31),
      ),
    ]);

    for (final scale in [1.0, 2.0, 3.2]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Words.localizationsDelegates,
          supportedLocales: Words.supportedLocales,
          theme: viewerTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: DecisionDetailScreen(
              store: store,
              decisionId: 31,
              projectName: 'viewer',
              onOpenTask: (_) {},
              onOpenDecision: (_) {},
              clock: () => today,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'nothing broke at $scale');
    }
  });
}
