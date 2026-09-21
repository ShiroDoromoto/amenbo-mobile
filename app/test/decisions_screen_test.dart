// The decisions face: everything there is, newest first, and a row that opens what it names.

import 'package:amenbo_viewer/decisions_screen.dart';
import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/ui/decision_row.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';
import 'words_fixture.dart';

final today = DateTime(2026, 8, 9, 12);

void main() {
  late BacklogStore store;
  late List<int> opened;

  setUp(() {
    store = BacklogStore.openInMemory();
    opened = [];
  });
  tearDown(() => store.close());

  Widget screen({Future<void> Function()? take}) => MaterialApp(
    localizationsDelegates: Words.localizationsDelegates,
    supportedLocales: Words.supportedLocales,
    theme: viewerTheme(Brightness.light),
    home: DecisionsScreen(
      store: store,
      clock: () => today,
      take: take,
      onOpen: (line) => opened.add(line.id),
    ),
  );

  testWidgets('the newest is at the top', (tester) async {
    store.applyPage([
      BacklogChange.put(
        'decision',
        1,
        decision(id: 1, title: 'さきにきめた', createdAt: '2026-08-01T00:00:00Z'),
      ),
      BacklogChange.put(
        'decision',
        2,
        decision(id: 2, title: 'あとできめた', createdAt: '2026-08-05T00:00:00Z'),
      ),
    ]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    final rows = tester.widgetList<DecisionRow>(find.byType(DecisionRow));
    expect(rows.map((row) => row.line.title), ['あとできめた', 'さきにきめた']);
  });

  testWidgets('nothing is left out for being unfinished or turned down', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('decision', 1, decision(id: 1, title: 'まだかきかけ')),
      BacklogChange.put(
        'decision',
        2,
        decision(
          id: 2,
          title: 'ことわった',
          status: 'rejected',
          draft: false,
          decidedAt: '2026-08-02T00:00:00Z',
        ),
      ),
    ]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    // The half-written one is the one most worth reading, and a rejected one is why something is
    // not the way somebody remembers arguing for.
    expect(decisionRowTitled(1, 'まだかきかけ'), findsOneWidget);
    expect(decisionRowTitled(2, 'ことわった'), findsOneWidget);
  });

  testWidgets('a row opens the decision it names', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 7, decision(id: 7, title: 'ひらくもの')),
    ]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(decisionRowTitled(7, 'ひらくもの'));

    expect(opened, [7]);
  });

  group('every project, unless one is picked', () {
    setUp(
      () => store.applyPage([
        BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
        BacklogChange.put('project', 20, project(id: 20, name: 'nsys')),
        BacklogChange.put(
          'decision',
          1,
          decision(id: 1, projectId: 16, title: 'こちらのきめごと'),
        ),
        BacklogChange.put(
          'decision',
          2,
          decision(id: 2, projectId: 20, title: 'むこうのきめごと'),
        ),
      ]),
    );

    testWidgets('it opens on every project stacked together', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      // Nothing has been asked of the person before the first row can be read.
      expect(find.byType(DecisionRow), findsNWidgets(2));
      expect(find.text('viewer'), findsOneWidget);
      expect(find.text('nsys'), findsOneWidget);
    });

    testWidgets('picking one leaves that project on the list', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();

      expect(decisionRowTitled(1, 'こちらのきめごと'), findsOneWidget);
      expect(decisionRowTitled(2, 'むこうのきめごと'), findsNothing);
      // And the name comes off the rows: the person picked it, and repeating it down every row
      // takes width off the titles.
      expect(find.text('viewer'), findsNothing);
    });

    testWidgets('and every project can be picked back', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();
      expect(find.byType(DecisionRow), findsOneWidget);

      await tester.tap(find.byTooltip(words.chooseProject));
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.allProjects).last);
      await tester.pumpAndSettle();

      expect(find.byType(DecisionRow), findsNWidgets(2));
    });
  });

  testWidgets('with one project there is nothing to choose between', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
      BacklogChange.put('decision', 1, decision(id: 1, projectId: 16)),
    ]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.byTooltip(words.chooseProject), findsNothing);
  });

  testWidgets('the end of a window asks for the next one', (tester) async {
    store.applyPage([
      for (var id = 1; id <= Windows.list + 3; id++)
        BacklogChange.put(
          'decision',
          id,
          decision(
            id: id,
            title: 'きめた $id',
            // A day each, so the order the window walks is the order they were made.
            createdAt: '2026-06-${id.toString().padLeft(2, '0')}T00:00:00Z',
          ),
        ),
    ]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    // The oldest three are behind the first window, and reaching the end of it is what asks.
    expect(decisionRowTitled(1, 'きめた 1'), findsNothing);
    await tester.scrollUntilVisible(decisionRowTitled(1, 'きめた 1'), 400);
    await tester.pumpAndSettle();
    expect(decisionRowTitled(1, 'きめた 1'), findsOneWidget);
  });

  testWidgets('a phone that has none is told where they come from', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    // Not an empty list: what to do about it is on the screen, which is the one thing an empty
    // list cannot say.
    expect(find.text(words.nothingHereYet), findsOneWidget);
    expect(find.text(words.nothingHereYetDetail), findsOneWidget);
  });

  testWidgets('a pull fetches and puts what came back in', (tester) async {
    store.applyPage([
      BacklogChange.put('decision', 1, decision(id: 1, title: 'もうあるもの')),
    ]);
    var rounds = 0;

    await tester.pumpWidget(
      screen(
        take: () async {
          rounds += 1;
          store.applyPage([
            BacklogChange.put(
              'decision',
              2,
              decision(
                id: 2,
                title: 'とどいたもの',
                createdAt: '2026-08-08T00:00:00Z',
              ),
            ),
          ]);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(decisionRowTitled(2, 'とどいたもの'), findsNothing);

    await tester.fling(
      find.byType(DecisionRow).first,
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(rounds, 1);
    // The person asked for it, so it goes in where they are looking.
    expect(decisionRowTitled(2, 'とどいたもの'), findsOneWidget);
  });
}
