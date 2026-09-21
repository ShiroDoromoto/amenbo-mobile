// The search face: two tabs, nothing excluded by state, newest first, and every way of arriving
// at a list arriving at this one.

import 'package:amenbo_viewer/search_screen.dart';
import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/store/recents.dart';
import 'package:amenbo_viewer/ui/decision_row.dart';
import 'package:amenbo_viewer/ui/marks.dart';
import 'package:amenbo_viewer/ui/task_row.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';
import 'words_fixture.dart';

final today = DateTime(2026, 8, 9, 12);

/// Shorter than the wait a finger really gets, so a test types and then lets it settle.
const settle = Duration(milliseconds: 10);

void main() {
  late BacklogStore store;
  late List<int> tasksOpened;
  late List<int> decisionsOpened;

  setUp(() {
    store = BacklogStore.openInMemory();
    tasksOpened = [];
    decisionsOpened = [];
  });
  tearDown(() => store.close());

  Widget screen({TaskQuery narrowing = const TaskQuery()}) => MaterialApp(
    localizationsDelegates: Words.localizationsDelegates,
    supportedLocales: Words.supportedLocales,
    theme: viewerTheme(Brightness.light),
    home: SearchScreen(
      store: store,
      narrowing: narrowing,
      clock: () => today,
      settle: settle,
      onOpenTask: (line) => tasksOpened.add(line.id),
      onOpenDecision: (line) => decisionsOpened.add(line.id),
    ),
  );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(settle * 2);
    await tester.pumpAndSettle();
  }

  group('what is looked for is usually finished', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(
            id: 1,
            title: 'QR に載せるものを決める',
            status: 'done',
            completedAt: '2026-08-02T00:00:00Z',
          ),
        ),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, title: 'ペアリングの案内を書く', notes: 'QR を読んでペアリングする'),
        ),
        BacklogChange.put(
          'task',
          3,
          task(id: 3, title: '署名鍵を用意する', status: 'rejected'),
        ),
        BacklogChange.put(
          'decision',
          7,
          decision(id: 7, title: 'QR に何を載せるか', draft: false),
        ),
      ]),
    );

    testWidgets('a done task and a rejected one are both results', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await type(tester, 'QR');

      expect(taskRowTitled(1, 'QR に載せるものを決める'), findsOneWidget);
      expect(taskRowTitled(2, 'ペアリングの案内を書く'), findsOneWidget);
      // Nothing was filtered out for being closed — the state is written on the row instead.
      expect(find.text(statusWords(words, 'done')), findsOneWidget);
    });

    testWidgets('a hit in a body says the line it hit', (tester) async {
      await tester.pumpWidget(screen());
      await type(tester, 'ペアリング');

      final hit = store
          .tasks(const TaskQuery(text: 'ペアリング'))
          .singleWhere((row) => row.id == 2);
      expect(hit.matchedIn, 'title');
      // Matched in the title: the row is already the line, and printing it twice would say only
      // that the search worked.
      expect(hit.matchLine, isNull);
      expect(taskRowTitled(2, 'ペアリングの案内を書く'), findsOneWidget);

      await type(tester, 'QR を読んで');
      final body = store
          .tasks(const TaskQuery(text: 'QR を読んで'))
          .singleWhere((row) => row.id == 2);
      expect(body.matchLine, isNotNull);
      expect(find.text(body.matchLine!.trim()), findsOneWidget);
    });

    testWidgets('both tabs carry their own count', (tester) async {
      await tester.pumpWidget(screen());
      await type(tester, 'QR');

      expect(
        find.text(
          SearchScreen.tab(words, words.tabTasks, const Counted(2, false)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          SearchScreen.tab(words, words.tabDecisions, const Counted(1, false)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the decisions tab reaches one nothing links to', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();

      expect(find.byType(DecisionRow), findsOneWidget);
      await tester.tap(decisionRowTitled(7, 'QR に何を載せるか'));
      expect(decisionsOpened, [7]);
    });

    testWidgets('an empty field lists what there is, newest first', (
      tester,
    ) async {
      await tester.pumpWidget(screen());

      expect(find.byType(TaskRow), findsNWidgets(3));
      expect(find.text(words.nothingMatched), findsNothing);
    });

    testWidgets('nothing matching says so without emptying the screen', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await type(tester, 'まったく出てこない語');

      expect(find.text(words.nothingMatched), findsOneWidget);
    });
  });

  group('the narrowing that arrived can be taken off', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, status: 'in_progress')),
        BacklogChange.put('task', 2, task(id: 2, title: 'つぎのしごと')),
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
      ]),
    );

    testWidgets('a chip from a detail opens here, holding what was pressed', (
      tester,
    ) async {
      await tester.pumpWidget(screen(narrowing: const TaskQuery(valueId: 1)));

      expect(find.byType(TaskRow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();

      // Taken off, this is plain search over everything.
      expect(find.byType(TaskRow), findsNWidgets(2));
    });

    testWidgets('a category value is a chip that says what it narrows to', (
      tester,
    ) async {
      await tester.pumpWidget(screen(narrowing: const TaskQuery(valueId: 1)));

      expect(find.text('Area: app'), findsOneWidget);
      expect(find.byType(TaskRow), findsOneWidget);
    });
  });

  group('an empty screen says what to do next', () {
    testWidgets('a search that answered nothing offers everything back', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'ペアリングの案内を書く')),
      ]);

      await tester.pumpWidget(screen());
      await type(tester, 'こんな語はどこにも書いていない');

      expect(find.text(words.nothingMatched), findsOneWidget);
      expect(find.text(words.nothingMatchedDetail), findsOneWidget);

      await tester.tap(find.text(words.showEverything));
      await tester.pumpAndSettle();

      expect(taskRowTitled(1, 'ペアリングの案内を書く'), findsOneWidget);
    });

    testWidgets('it drops the narrowing too, not only the words', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'つぎのしごと')),
      ]);

      // A category value nothing on this phone wears, arrived at from a detail.
      await tester.pumpWidget(screen(narrowing: const TaskQuery(valueId: 99)));
      expect(find.text(words.nothingMatched), findsOneWidget);

      await tester.tap(find.text(words.showEverything));
      await tester.pumpAndSettle();

      expect(taskRowTitled(1, 'つぎのしごと'), findsOneWidget);
      // The chip went with it: what is on the screen and what is being searched agree.
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('it still fits at the largest text a phone offers', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0, 3.2]) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: Words.localizationsDelegates,
            supportedLocales: Words.supportedLocales,
            theme: viewerTheme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SearchScreen(
                store: store,
                clock: () => today,
                settle: settle,
                narrowing: const TaskQuery(text: 'どこにも書いていない語'),
                onOpenTask: (_) {},
                onOpenDecision: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(words.nothingMatched), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'nothing broke at $scale',
        );
      }
    });

    testWidgets('a phone the PC has not fed yet is told where to go', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text(words.nothingHereYet), findsOneWidget);
      expect(find.text(words.nothingHereYetDetail), findsOneWidget);
      // The fetch is on the other screen. Nothing here pretends to offer it.
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('every project, unless one is picked', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
        BacklogChange.put(
          'project',
          20,
          project(id: 20, name: 'むかしの', archived: 1),
        ),
        BacklogChange.put('task', 1, task(id: 1, projectId: 16)),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, projectId: 20, title: 'アーカイブのしごと'),
        ),
      ]),
    );

    testWidgets('an archived project is dropped from the bundles, not here', (
      tester,
    ) async {
      await tester.pumpWidget(screen());

      expect(taskRowTitled(2, 'アーカイブのしごと'), findsOneWidget);
      // And it can be picked out, which is the whole reason it is kept.
      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text('むかしの').last);
      await tester.pumpAndSettle();

      expect(find.byType(TaskRow), findsOneWidget);
    });

    testWidgets('and every project can be picked back', (tester) async {
      await tester.pumpWidget(screen());

      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text('むかしの').last);
      await tester.pumpAndSettle();
      expect(find.byType(TaskRow), findsOneWidget);

      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.allProjects).last);
      await tester.pumpAndSettle();

      expect(find.byType(TaskRow), findsNWidgets(2));
    });

    testWidgets('the project that arrived with the person comes off too', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen(narrowing: const TaskQuery(projectId: 16)),
      );

      expect(find.byType(TaskRow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(TaskRow), findsNWidgets(2));
    });
  });

  group('the state is said once', () {
    testWidgets('a blocked row with nothing named carries the state alone', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, status: 'blocked')),
      ]);

      await tester.pumpWidget(screen());

      // The mark a row standing on its own carries says the state. The place beside it is for
      // naming what to go and do, and Amenbo's bare `blocked` names nothing — put there as well,
      // it only said the state twice.
      expect(find.byType(StatusMark), findsOneWidget);
      expect(find.byType(StallMark), findsNothing);
    });

    testWidgets('a blocker with a name still gets its own line', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('task', 2, task(id: 2, status: 'blocked')),
        BacklogChange.put(
          'task_dependency',
          1,
          dependency(id: 1, taskId: 2, blockedById: 1),
        ),
      ]);

      await tester.pumpWidget(screen());

      expect(find.byType(StallMark), findsOneWidget);
    });
  });

  group('the same thing is looked up twice', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'おぼえられるしごと')),
        BacklogChange.put('task', 2, task(id: 2, title: 'べつのしごと')),
      ]),
    );

    testWidgets('the word that led somewhere, and the row it led to, come back', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await type(tester, 'おぼえられる');
      await tester.tap(taskRowTitled(1, 'おぼえられるしごと'));
      expect(tasksOpened, [1]);

      // Coming back to it another time, on an empty field: both shortcuts are standing there.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      expect(find.text(words.recentTerms), findsOneWidget);
      expect(find.text(words.recentlyOpened), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'おぼえられる'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskRow), findsOneWidget);
    });

    testWidgets('it outlives the store being emptied and refilled', (
      tester,
    ) async {
      store.remember(term: 'のこるはず');
      store.wipe();

      expect(store.recentTerms(), ['のこるはず']);
    });
  });

  testWidgets('the window grows by a window, not by the whole backlog', (
    tester,
  ) async {
    store.applyPage([
      for (var id = 1; id <= Windows.list + 5; id++)
        BacklogChange.put('task', id, task(id: id, title: 'しごと $id')),
    ]);

    await tester.pumpWidget(screen());
    // One window is what the screen asked for; the tail of the backlog is not there yet.
    expect(store.tasks(const TaskQuery()), hasLength(Windows.list));
    expect(taskRowTitled(1, 'しごと 1', skipOffstage: false), findsNothing);

    // Reaching the end of the window asks for the next one, and the oldest row turns up.
    await tester.scrollUntilVisible(
      taskRowTitled(1, 'しごと 1'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(taskRowTitled(1, 'しごと 1'), findsOneWidget);
  });

  testWidgets('nothing overflows at the largest text a phone offers', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
      BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
      BacklogChange.put(
        'task',
        1,
        task(
          id: 1,
          title:
              'a backlog title long enough that it cannot possibly fit on one '
              'line even before anybody turns their text size up',
          notes: 'ペアリング のことが本文に書いてあって、抜粋がそこから出てくる',
          status: 'done',
          completedAt: '2026-08-02T00:00:00Z',
        ),
      ),
      BacklogChange.put('decision', 1, decision(id: 1, title: 'ペアリング の形を決める')),
    ]);

    for (final scale in [1.0, 2.0, 3.2]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Words.localizationsDelegates,
          supportedLocales: Words.supportedLocales,
          theme: viewerTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SearchScreen(
              store: store,
              clock: () => today,
              settle: settle,
              narrowing: const TaskQuery(text: 'ペアリング'),
              onOpenTask: (_) {},
              onOpenDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nothing broke at $scale');
    }
  });
}
