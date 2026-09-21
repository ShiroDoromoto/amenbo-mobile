// The front screen: the four states switched between, every project at once unless the person
// says otherwise, and a floor that is never swapped while they are standing on it.

import 'package:amenbo_viewer/cloudflare_intake.dart';
import 'package:amenbo_viewer/now_screen.dart';
import 'package:amenbo_viewer/state_band.dart';
import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/ui/project_choice.dart';
import 'package:amenbo_viewer/ui/task_row.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/ui/time.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';
import 'words_fixture.dart';

/// One day for the whole file, so a row and the heading over it cannot disagree about it.
final today = DateTime(2026, 8, 9, 12);

/// A round that finished at a wall-clock moment, in the shape the store keeps it in. Written from
/// a local time rather than a literal, so what the screen says is the hour that was passed in
/// wherever the test is run.
String stamp(DateTime when) => when.toUtc().toIso8601String();

void main() {
  late BacklogStore store;
  late Arrivals arrivals;
  late List<int> opened;

  setUp(() {
    store = BacklogStore.openInMemory();
    arrivals = Arrivals();
    opened = [];
  });
  tearDown(() {
    arrivals.dispose();
    store.close();
  });

  // The clock this screen writes is the phone's, so which one the phone was set to is part of the
  // harness rather than whatever a test machine happens to default to.
  Widget screen({
    Future<void> Function()? take,
    IntakeFailure? failure,
    bool hours24 = true,
    bool stillness = false,
  }) => MaterialApp(
    localizationsDelegates: Words.localizationsDelegates,
    supportedLocales: Words.supportedLocales,
    theme: viewerTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(
        alwaysUse24HourFormat: hours24,
        disableAnimations: stillness,
      ),
      child: NowScreen(
        store: store,
        take: take,
        failure: failure,
        arrivals: arrivals,
        clock: () => today,
        onOpen: (line) => opened.add(line.id),
      ),
    ),
  );

  /// The finished state, reached the way a person reaches it — by its own switch, which carries
  /// the number in it.
  Future<void> openFinished(WidgetTester tester, int count) async {
    await tester.tap(
      find.text(
        NowScreen.tab(words, TaskState.finished, Counted(count, false)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what the switch says', () {
    test('a state is named and counted in one', () {
      expect(
        NowScreen.tab(words, TaskState.todo, const Counted(3, false)),
        'To do 3',
      );
    });

    test('a count that stopped counting says so instead of lying', () {
      // `999+` is not a number, so nothing in any language can agree with it. It arrives as text.
      expect(
        NowScreen.tab(
          words,
          TaskState.finished,
          const Counted(Counted.cap, true),
        ),
        'Done 999+',
      );
    });
  });

  group('how old this is, and the way to a newer one', () {
    testWidgets('the two halves are read together, in words', (tester) async {
      var takes = 0;
      store.setMeta(MetaKey.fetchedAt, stamp(DateTime(2026, 8, 9, 12, 34)));
      await tester.pumpWidget(screen(take: () async => takes++));

      // The clock, not "3 h ago": a phone whose clock is out can still name the hour.
      expect(find.text('Taken 12:34'), findsOneWidget);
      // And the way to a newer one beside it: the circling arrows, wearing the word rather than
      // printing it, so the one-line top spends its width on the hour.
      expect(find.byIcon(Icons.refresh), findsWidgets);
      await tester.tap(find.byTooltip(words.refresh).first);
      await tester.pumpAndSettle();
      expect(takes, 1);
    });

    testWidgets('the hour is written the way the phone writes hours', (
      tester,
    ) async {
      store.setMeta(MetaKey.fetchedAt, stamp(DateTime(2026, 8, 9, 12, 34)));
      await tester.pumpWidget(screen(hours24: false));

      // The phone's own switch decides, not the language's habit — and English, left alone, asks
      // for twelve hours. The gap before PM is the narrow one the language's data asks for.
      expect(find.text('Taken 12:34\u202fPM'), findsOneWidget);
    });

    testWidgets('a picture from another day is dated, not just clocked', (
      tester,
    ) async {
      // The line is all a phone out of signal has to judge what it is reading by, and an hour on
      // its own reads as this morning's however many nights ago it was taken.
      for (final (taken, said) in [
        (DateTime(2026, 8, 8, 9, 14), 'Taken yesterday 09:14'),
        (DateTime(2026, 8, 2, 9, 14), 'Taken Aug 2 09:14'),
        (DateTime(2025, 12, 30, 9, 14), 'Taken Dec 30, 2025 09:14'),
      ]) {
        store.setMeta(MetaKey.fetchedAt, stamp(taken));
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.text(said), findsOneWidget);
        // Torn down between the rounds: the screen reads the stamp when it is built, so a second
        // one built over the first would still be showing the first one's hour.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('the line is there before any round has finished', (
      tester,
    ) async {
      await tester.pumpWidget(screen(take: () async {}));

      // Nothing to date yet, and the way to go and get something is still on the screen — an
      // operation nobody can find until it has already happened is one nobody finds.
      expect(find.textContaining('Taken'), findsNothing);
      expect(find.byTooltip(words.refresh), findsWidgets);
    });

    testWidgets('a phone with no route to take is offered nothing to press', (
      tester,
    ) async {
      await tester.pumpWidget(screen());

      expect(find.byTooltip(words.refresh), findsNothing);
    });
  });

  group('how things stand sits above the picture, never in place of it', () {
    testWidgets('offline keeps every row readable', (tester) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'よめる')),
      ]);
      store.setMeta(MetaKey.fetchedAt, '2026-08-09T03:34:00Z');

      await tester.pumpWidget(screen(failure: IntakeFailure.unreachable));

      expect(find.text(standingWords(words, Standing.offline)), findsOneWidget);
      // The whole promise: what is on the device stays readable whatever the network did.
      expect(taskRowTitled(1, 'よめる'), findsOneWidget);
    });

    testWidgets('a device that never got anything is told which of the two', (
      tester,
    ) async {
      await tester.pumpWidget(screen(failure: IntakeFailure.tooNew));

      // Not "nothing has arrived yet" — something did, and this build cannot read it.
      expect(find.text(standingWords(words, Standing.tooNew)), findsOneWidget);
      expect(find.text(standingWords(words, Standing.waiting)), findsNothing);
    });
  });

  group('the four states, switched between', () {
    testWidgets('every state is on the switch, with how many are in it', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, status: 'in_progress')),
        BacklogChange.put('task', 2, task(id: 2, status: 'blocked')),
        BacklogChange.put('task', 3, task(id: 3)),
      ]);

      await tester.pumpWidget(screen());

      // Including the one with nothing in it: a state is not on the switch because it has rows,
      // and "0 blocked" is the answer somebody came to read.
      expect(
        find.text(
          NowScreen.tab(words, TaskState.todo, const Counted(1, false)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          NowScreen.tab(words, TaskState.inProgress, const Counted(1, false)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          NowScreen.tab(words, TaskState.blocked, const Counted(1, false)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          NowScreen.tab(words, TaskState.finished, const Counted(0, false)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('it opens on what is next, and the rest is one press away', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'これから')),
        BacklogChange.put(
          'task',
          2,
          task(id: 2, title: 'いま動いている', status: 'in_progress'),
        ),
      ]);

      await tester.pumpWidget(screen());
      expect(taskRowTitled(1, 'これから'), findsOneWidget);
      expect(taskRowTitled(2, 'いま動いている'), findsNothing);

      await tester.tap(
        find.text(
          NowScreen.tab(words, TaskState.inProgress, const Counted(1, false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(taskRowTitled(2, 'いま動いている'), findsOneWidget);
      expect(taskRowTitled(1, 'これから'), findsNothing);
    });

    testWidgets('a row waiting on something stays in todo and says so', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        BacklogChange.put('task', 5, task(id: 5)),
        BacklogChange.put(
          'task_dependency',
          1,
          dependency(id: 1, taskId: 5, blockedById: 1),
        ),
      ]);

      await tester.pumpWidget(screen());

      final line = store
          .inState(TaskState.todo, today: today)
          .singleWhere((row) => row.id == 5);
      expect(find.text(stallReason(face, line, today: today)!), findsOneWidget);
      // Both rows are here — the one that can be started is not lifted out of the list, it is
      // simply the one with no waiting mark on it.
      expect(find.byType(TaskRow), findsNWidgets(2));
    });

    testWidgets('a day that has not come is a reason like any other', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, startOn: '2026-09-01')),
      ]);

      await tester.pumpWidget(screen());

      // Even the one stall nobody has to do anything about: a row that says nothing about why it
      // is waiting is the row that wastes its second line.
      expect(find.textContaining('Starts'), findsOneWidget);
    });

    testWidgets('only the rows in progress carry a time', (tester) async {
      const moved = '2026-08-01T00:00:00Z';
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, status: 'in_progress', updatedAt: moved),
        ),
        BacklogChange.put('task', 2, task(id: 2, updatedAt: moved)),
      ]);

      await tester.pumpWidget(screen());
      final when = find.text(
        relativeTime(face, DateTime.parse(moved), now: today),
      );
      // Not on the state it opens on.
      expect(when, findsNothing);

      await tester.tap(
        find.text(
          NowScreen.tab(words, TaskState.inProgress, const Counted(1, false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(when, findsOneWidget);
    });

    testWidgets('the finished state holds work of any age', (tester) async {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(
            id: 1,
            title: 'きょねん終わった',
            status: 'done',
            completedAt: '2025-01-06T06:00:00Z',
          ),
        ),
        // So the phone is not one with nothing on it, which is a screen of its own.
        BacklogChange.put('task', 2, task(id: 2)),
      ]);

      await tester.pumpWidget(screen());
      await openFinished(tester, 1);

      // The device holds the whole copy, so nothing is behind a cut-off to go and fetch — and a
      // row that is old is still a row the person finished.
      expect(taskRowTitled(1, 'きょねん終わった'), findsOneWidget);
    });

    testWidgets('the date is written in wherever it changes', (tester) async {
      store.applyPage([
        for (final (id, closed) in const [
          (1, '2026-08-08T06:00:00Z'),
          (2, '2026-08-08T07:00:00Z'),
          (3, '2026-08-05T06:00:00Z'),
        ])
          BacklogChange.put(
            'task',
            id,
            task(id: id, title: 'しごと $id', status: 'done', completedAt: closed),
          ),
        BacklogChange.put('task', 4, task(id: 4)),
      ]);

      await tester.pumpWidget(screen());
      await openFinished(tester, 3);

      // Two days, so two headings — the pair that ended on the same day share theirs, or the
      // heading would be a line repeated over every row instead of a place in the list.
      expect(find.byType(ListHeading), findsNWidgets(2));
      for (final closed in const [
        '2026-08-08T06:00:00Z',
        '2026-08-05T06:00:00Z',
      ]) {
        expect(
          find.text(dateHeading(face, DateTime.parse(closed), now: today)),
          findsOneWidget,
        );
      }
    });

    testWidgets('one state is read to its end, not handed to another face', (
      tester,
    ) async {
      store.applyPage([
        for (var id = 1; id <= Windows.list + 3; id++)
          BacklogChange.put('task', id, task(id: id, title: 'しごと $id')),
      ]);

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        taskRowTitled(Windows.list + 3, 'しごと ${Windows.list + 3}'),
        findsNothing,
      );

      // Reaching the bottom is the whole of asking for more. The list being read is named, or
      // the switch and the row of states are scrollables too.
      await tester.scrollUntilVisible(
        taskRowTitled(Windows.list + 3, 'しごと ${Windows.list + 3}'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(TabBarView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        taskRowTitled(Windows.list + 3, 'しごと ${Windows.list + 3}'),
        findsOneWidget,
      );
    });

    testWidgets('a state with nothing in it says so, quietly', (tester) async {
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);

      await tester.pumpWidget(screen());
      await tester.tap(
        find.text(
          NowScreen.tab(words, TaskState.blocked, const Counted(0, false)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(words.nothingInState), findsOneWidget);
    });

    testWidgets('a row opens the task it names', (tester) async {
      store.applyPage([
        BacklogChange.put('task', 42, task(id: 42, title: 'ひらく')),
      ]);

      await tester.pumpWidget(screen());
      await tester.tap(taskRowTitled(42, 'ひらく'));
      expect(opened, [42]);
    });
  });

  group('projects narrow, they do not divide', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
        BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
        BacklogChange.put('task', 1, task(id: 1, projectId: 16)),
        BacklogChange.put('task', 2, task(id: 2, projectId: 20)),
      ]),
    );

    testWidgets('everything is stacked together, and each row says where', (
      tester,
    ) async {
      await tester.pumpWidget(screen());

      expect(find.text(words.allProjects), findsOneWidget);
      expect(find.byType(TaskRow), findsNWidgets(2));
      expect(find.text('viewer'), findsOneWidget);
      expect(find.text('nsys'), findsOneWidget);
    });

    testWidgets('choosing one narrows the list and stops repeating its name', (
      tester,
    ) async {
      await tester.pumpWidget(screen());

      await tester.tap(find.text(words.allProjects));
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();

      expect(find.byType(TaskRow), findsOneWidget);
      // Once only — the title. Repeating it down every row buys nothing and costs width.
      expect(find.text('viewer'), findsOneWidget);
    });

    testWidgets('and it can be picked back off', (tester) async {
      await tester.pumpWidget(screen());

      await tester.tap(find.text(words.allProjects));
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();
      expect(find.byType(TaskRow), findsOneWidget);

      await tester.tap(find.text('viewer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.allProjects).last);
      await tester.pumpAndSettle();

      expect(find.byType(TaskRow), findsNWidgets(2));
      expect(find.text(words.allProjects), findsOneWidget);
    });

    testWidgets('one project is a title, not a menu', (tester) async {
      final alone = BacklogStore.openInMemory();
      addTearDown(alone.close);
      alone.applyPage([
        BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
        BacklogChange.put('task', 1, task(id: 1, projectId: 16)),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Words.localizationsDelegates,
          supportedLocales: Words.supportedLocales,
          home: NowScreen(store: alone, clock: () => today, onOpen: (_) {}),
        ),
      );

      expect(find.text('viewer'), findsOneWidget);
      expect(find.byType(PopupMenuButton<ProjectChoice>), findsNothing);
    });
  });

  group('the floor is not swapped while it is being read', () {
    testWidgets('rows that arrive on their own wait behind a pill', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'よんでいる', updatedAt: '2026-08-09T09:00:00Z'),
        ),
      ]);
      await tester.pumpWidget(screen());

      store.applyPage([
        BacklogChange.put(
          'task',
          2,
          task(id: 2, title: 'あとから', updatedAt: '2026-08-09T09:05:00Z'),
        ),
      ]);
      arrivals.tick();
      await tester.pumpAndSettle();

      expect(taskRowTitled(2, 'あとから'), findsNothing);
      expect(
        find.text(NowScreen.arrived(words, const Counted(1, false))),
        findsOneWidget,
      );

      await tester.tap(
        find.text(NowScreen.arrived(words, const Counted(1, false))),
      );
      await tester.pumpAndSettle();
      expect(taskRowTitled(2, 'あとから'), findsOneWidget);
      expect(find.textContaining('New activity'), findsNothing);
    });

    testWidgets('the pill drops in and leaves, rather than blinking', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'よんでいる', updatedAt: '2026-08-09T09:00:00Z'),
        ),
      ]);
      await tester.pumpWidget(screen());

      store.applyPage([
        BacklogChange.put(
          'task',
          2,
          task(id: 2, title: 'あとから', updatedAt: '2026-08-09T09:05:00Z'),
        ),
      ]);
      arrivals.tick();
      await tester.pump();

      final pill = find.byType(ActionChip);
      final coming = tester.getTopLeft(pill).dy;
      await tester.pumpAndSettle();
      // It came down from above the top edge — the place it is offering to take the reader back
      // to — instead of being there all at once.
      expect(tester.getTopLeft(pill).dy, greaterThan(coming));

      await tester.tap(pill);
      // Still on its way out one frame later. The list underneath is never animated, so the pill
      // leaving is the whole of what says the rows went in.
      await tester.pump();
      expect(pill, findsOneWidget);
      await tester.pumpAndSettle();
      expect(pill, findsNothing);
    });

    testWidgets('a phone asked to move less is handed the pill in place', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'よんでいる', updatedAt: '2026-08-09T09:00:00Z'),
        ),
      ]);
      await tester.pumpWidget(screen(stillness: true));

      store.applyPage([
        BacklogChange.put(
          'task',
          2,
          task(id: 2, title: 'あとから', updatedAt: '2026-08-09T09:05:00Z'),
        ),
      ]);
      arrivals.tick();
      await tester.pump();

      final pill = find.byType(ActionChip);
      final atOnce = tester.getTopLeft(pill).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pill).dy, atOnce);

      await tester.tap(pill);
      await tester.pump();
      expect(pill, findsNothing);
    });

    testWidgets('a list with nothing in it fills as the rows land', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      expect(find.text(standingWords(words, Standing.waiting)), findsOneWidget);

      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'とどいた')),
      ]);
      arrivals.tick();
      await tester.pumpAndSettle();

      // Nobody is mid-read, and a first sync is meant to be watched arriving.
      expect(taskRowTitled(1, 'とどいた'), findsOneWidget);
      expect(find.textContaining('New activity'), findsNothing);
    });

    testWidgets('rows somebody sat and watched land are not held back', (
      tester,
    ) async {
      // Pairing again from a phone that already holds a backlog. The person watched this round
      // fill a screen of its own, so a pill offering it would be offering them what they just
      // waited for.
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'まえから')),
      ]);
      await tester.pumpWidget(screen());

      store.applyPage([
        BacklogChange.put('task', 2, task(id: 2, title: 'みていた')),
      ]);
      arrivals.tick(watched: true);
      await tester.pumpAndSettle();

      expect(taskRowTitled(2, 'みていた'), findsOneWidget);
      expect(find.textContaining('New activity'), findsNothing);
    });

    testWidgets('asking for it applies it there and then', (tester) async {
      var takes = 0;
      await tester.pumpWidget(
        screen(
          take: () async {
            takes++;
            store.applyPage([
              BacklogChange.put('task', 1, task(id: 1, title: 'ひっぱった')),
            ]);
          },
        ),
      );

      await tester.tap(find.byTooltip(words.refresh).first);
      await tester.pumpAndSettle();

      expect(takes, 1);
      expect(taskRowTitled(1, 'ひっぱった'), findsOneWidget);
      expect(find.textContaining('New activity'), findsNothing);
    });

    testWidgets('a fetch that failed leaves the picture it had', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'のこる')),
      ]);
      await tester.pumpWidget(screen(take: () async => throw Exception('off')));

      await tester.tap(find.byTooltip(words.refresh).first);
      await tester.pumpAndSettle();

      expect(taskRowTitled(1, 'のこる'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('nothing overflows at the largest text a phone offers', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
      BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
      BacklogChange.put('task', 1, task(id: 1)),
      BacklogChange.put(
        'task',
        5,
        task(
          id: 5,
          title:
              'a backlog title long enough that it cannot possibly fit on one '
              'line even before anybody turns their text size up',
          assigneeKind: 'ai',
        ),
      ),
      BacklogChange.put(
        'task_dependency',
        1,
        dependency(id: 1, taskId: 5, blockedById: 1),
      ),
      BacklogChange.put('task_comment', 1, comment(id: 1, taskId: 5)),
    ]);

    for (final scale in [1.0, 2.0, 3.2]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Words.localizationsDelegates,
          supportedLocales: Words.supportedLocales,
          theme: viewerTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: NowScreen(store: store, clock: () => today, onOpen: (_) {}),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'nothing broke at $scale');
    }
  });
}
