// The detail: read to the end in one pass, with the reason it cannot move standing above the
// notes, and nothing on the screen pretending the phone holds more than it does.

import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/task_detail.dart';
import 'package:amenbo_viewer/ui/marks.dart';
import 'package:amenbo_viewer/ui/refs.dart';
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

  Widget detail({int id = 1, String? project, void Function(int)? onProject}) =>
      MaterialApp(
        localizationsDelegates: Words.localizationsDelegates,
        supportedLocales: Words.supportedLocales,
        theme: viewerTheme(Brightness.light),
        home: TaskDetailScreen(
          store: store,
          taskId: id,
          projectName: project,
          onProject: onProject,
          onOpenTask: openedTasks.add,
          onOpenDecision: openedDecisions.add,
          onShare: (text) async => shared.add(text),
          clock: () => today,
        ),
      );

  testWidgets('the number, the project and the title lead', (tester) async {
    store.applyPage([BacklogChange.put('task', 1, task(id: 1, title: 'かく'))]);

    await tester.pumpWidget(
      detail(project: 'viewer', onProject: (_) => openedTasks.add(-1)),
    );

    expect(find.text(taskRef(1)), findsOneWidget);
    expect(find.text('viewer'), findsOneWidget);
    expect(find.text('かく'), findsOneWidget);

    await tester.tap(find.text('viewer'));
    expect(openedTasks, [-1]);
  });

  testWidgets('the bar goes on saying what is open once the head has gone', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put(
        'task',
        1,
        task(id: 1, title: 'かく', notes: List.filled(40, 'ほんぶん').join('\n\n')),
      ),
    ]);

    await tester.pumpWidget(detail());
    final name = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('かく'),
    );
    // While the head is showing, the bar would only be saying it twice.
    expect(name, findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    expect(name, findsOneWidget);
    // The number never leaves: it is what the person types on the PC.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(taskRef(1))),
      findsOneWidget,
    );
  });

  testWidgets('the reason it cannot start does not wear the body\'s face', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('task', 9, task(id: 9, title: 'さきに')),
      BacklogChange.put('task', 1, task(id: 1, notes: '```\nこーど\n```')),
      BacklogChange.put(
        'task_dependency',
        1,
        dependency(id: 1, taskId: 1, blockedById: 9),
      ),
    ]);

    await tester.pumpWidget(detail());

    BoxDecoration decorationOf(Finder of) => tester
        .widgetList<Container>(
          find.ancestor(of: of, matching: find.byType(Container)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .first;

    // The app's own remark is outlined; what somebody wrote into the record is a filled block.
    // Drawn on one surface, the remark reads as a line of the notes.
    final notice = decorationOf(find.textContaining('is not finished'));
    final code = decorationOf(find.text('こーど'));
    expect(notice.color, isNull);
    expect(notice.border, isNotNull);
    expect(code.color, isNotNull);
  });

  testWidgets('why it cannot move is above what it says', (tester) async {
    store.applyPage([
      BacklogChange.put('task', 9, task(id: 9, title: 'さきに')),
      BacklogChange.put('task', 1, task(id: 1, notes: '## やること\n\nこれをやる。')),
      BacklogChange.put(
        'task_dependency',
        1,
        dependency(id: 1, taskId: 1, blockedById: 9),
      ),
    ]);

    await tester.pumpWidget(detail());

    final reason = find.textContaining('is not finished');
    expect(reason, findsWidgets);
    // Reading the notes and finding out at the bottom is the one order that wastes the minutes.
    expect(
      tester.getTopLeft(reason.first).dy,
      lessThan(tester.getTopLeft(find.text('やること')).dy),
    );
  });

  testWidgets('the ties run both ways and say where the other side stands', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('task', 1, task(id: 1)),
      BacklogChange.put('task', 9, task(id: 9, title: 'さきに', status: 'done')),
      BacklogChange.put('task', 7, task(id: 7, title: 'あとに')),
      BacklogChange.put(
        'task_dependency',
        1,
        dependency(id: 1, taskId: 1, blockedById: 9),
      ),
      BacklogChange.put(
        'task_dependency',
        2,
        dependency(id: 2, taskId: 7, blockedById: 1),
      ),
      BacklogChange.put('decision', 31, decision(id: 31, title: 'きめごと')),
      BacklogChange.put(
        'decision_task_link',
        1,
        decisionLink(id: 1, decisionId: 31, taskId: 1),
      ),
    ]);

    await tester.pumpWidget(detail());

    expect(find.text(words.waitingOn), findsOneWidget);
    expect(find.text(words.waitedOnBy), findsOneWidget);
    // Whether the other one is finished is the whole of what waiting means.
    expect(find.textContaining('Done'), findsOneWidget);
    expect(
      find.textContaining(decisionStatusWords(words, 'draft')),
      findsWidgets,
    );

    await tester.tap(find.text('さきに'));
    expect(openedTasks, [9]);

    await tester.tap(find.text('きめごと'));
    expect(openedDecisions, [31]);
  });

  testWidgets('an attachment says the file is not here, and is not pressable', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put('task', 1, task(id: 1)),
      BacklogChange.put(
        'attachment',
        1,
        attachment(id: 1, targetId: 1, sizeBytes: 2048),
      ),
    ]);

    await tester.pumpWidget(detail());

    expect(find.text('shot.png'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.text(words.attachmentsStayOnThePc), findsOneWidget);
    // A row that looks pressable and does nothing is worse than one that never offered.
    expect(
      find.ancestor(of: find.text('shot.png'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('commits are a count until they are asked for', (tester) async {
    const sha = '0123456789abcdef0123456789abcdef01234567';
    store.applyPage([
      BacklogChange.put('task', 1, task(id: 1)),
      BacklogChange.put(
        'task_commit',
        1,
        taskCommit(id: 1, taskId: 1, sha: sha),
      ),
    ]);

    await tester.pumpWidget(detail());
    expect(find.text('${words.commits} 1'), findsOneWidget);
    expect(find.text(sha.substring(0, 12)), findsNothing);

    await tester.tap(find.text('${words.commits} 1'));
    await tester.pumpAndSettle();
    expect(find.text(sha.substring(0, 12)), findsOneWidget);
  });

  group('comments', () {
    void fill(int count) {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1)),
        for (var i = 1; i <= count; i++)
          BacklogChange.put(
            'task_comment',
            i,
            comment(
              id: i,
              taskId: 1,
              text: 'こめんと $i',
              createdAt: '2026-08-01T00:${i.toString().padLeft(2, '0')}:00Z',
            ),
          ),
      ]);
    }

    testWidgets('it opens on the newest few, oldest first, and walks back', (
      tester,
    ) async {
      fill(5);
      await tester.pumpWidget(detail());

      final shown = find.textContaining('こめんと');
      expect(shown, findsNWidgets(Windows.comments));
      // Read as a conversation: the oldest of the window is at the top of it.
      expect(
        tester.getTopLeft(shown.first).dy,
        lessThan(tester.getTopLeft(shown.last).dy),
      );

      await tester.tap(find.text(words.readEarlier));
      await tester.pumpAndSettle();
      expect(find.textContaining('こめんと'), findsNWidgets(5));
    });
  });

  group('the bridge back to the PC', () {
    testWidgets('three lines leave: the number, the title, where it stands', (
      tester,
    ) async {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'かく', status: 'in_progress', notes: 'ながいほんぶん'),
        ),
      ]);

      await tester.pumpWidget(detail());
      await tester.tap(find.byTooltip(words.share));

      // The notes stay on the PC: what travels is what makes the row findable there.
      expect(shared, ['${taskRef(1)}\nかく\nIn progress']);
    });
  });

  testWidgets('a task the phone does not hold says so instead of breaking', (
    tester,
  ) async {
    await tester.pumpWidget(detail(id: 4242));
    expect(find.text(words.taskGone), findsOneWidget);
    // Nothing to hand over either — a number with no task behind it is not a message.
    expect(find.byTooltip(words.share), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing overflows at the largest text a phone offers', (
    tester,
  ) async {
    store.applyPage([
      BacklogChange.put(
        'task',
        1,
        task(
          id: 1,
          title:
              'a backlog title long enough that it runs past one line before '
              'anybody turns their text up',
          notes: '## やること\n\n| 軸 | 値 |\n|---|---|\n| a | b |\n\n- ひとつ\n',
          assigneeKind: 'ai',
          dueOn: '2026-08-07',
        ),
      ),
      BacklogChange.put('task_comment', 1, comment(id: 1, taskId: 1)),
    ]);

    for (final scale in [1.0, 2.0, 3.2]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Words.localizationsDelegates,
          supportedLocales: Words.supportedLocales,
          theme: viewerTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: TaskDetailScreen(
              store: store,
              taskId: 1,
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
