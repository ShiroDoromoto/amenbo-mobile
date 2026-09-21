// The rules that hold across every screen, checked where they are decided rather than once per
// screen — a screen that forgets one of them looks right to whoever wrote it.

import 'dart:io';

import 'package:amenbo_viewer/main.dart';
import 'package:amenbo_viewer/settings.dart';
import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/ui/detail.dart';
import 'package:amenbo_viewer/ui/marks.dart';
import 'package:amenbo_viewer/ui/measure.dart';
import 'package:amenbo_viewer/ui/task_row.dart';
import 'package:amenbo_viewer/ui/refs.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/ui/time.dart';
import 'package:amenbo_viewer/ui/tokens.dart';
import 'package:amenbo_viewer/ui/two_pane.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'words_fixture.dart';

final now = DateTime(2026, 8, 9, 12, 0);

void main() {
  group('one look, both platforms', () {
    test('both brightnesses are drawn from the one sheet', () {
      for (final brightness in Brightness.values) {
        final theme = viewerTheme(brightness);
        final colours = paletteFor(brightness);
        expect(theme.colorScheme.brightness, brightness);
        // Amenbo's own colours, not ones Material derived for us: the two tools read the same
        // backlog, and someone who uses both must not meet two products.
        expect(theme.colorScheme.primary, colours.accent);
        expect(theme.colorScheme.surface, colours.bg);
        expect(theme.colorScheme.onSurface, colours.text);
        expect(theme.colorScheme.onSurfaceVariant, colours.textMuted);
        expect(theme.colorScheme.outlineVariant, colours.border);
      }
      // Both sides are written out. A dark theme that came out equal to the light one would mean
      // one of them was never copied.
      expect(
        viewerTheme(Brightness.dark).colorScheme.surface,
        isNot(viewerTheme(Brightness.light).colorScheme.surface),
      );
    });

    test('the text sizes are the sheet\'s, so the OS setting scales them', () {
      final text = viewerTheme(Brightness.light).textTheme;
      expect(text.titleMedium?.fontSize, Lettering.lg);
      expect(text.bodyMedium?.fontSize, Lettering.md);
      expect(text.labelMedium?.fontSize, Lettering.xs);
    });

    test('no typeface is shipped with the app', () {
      // Nineteen languages are coming, and carrying their glyphs would put tens of megabytes into
      // a thing that is opened for half a minute. Every one of them is drawn in the phone's own
      // face, which is what a pubspec with nothing under `fonts:` means.
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('fonts:')),
      );
    });

    testWidgets('a mark takes its colour from the sheet too', (tester) async {
      await tester.pumpWidget(_wrap(const PriorityMark('high')));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, lightPalette.priorityHigh);
    });

    testWidgets('the platform does not get a look of its own', (tester) async {
      final seen = <Color>{};
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: Words.localizationsDelegates,
            supportedLocales: Words.supportedLocales,
            theme: viewerTheme(Brightness.light).copyWith(platform: platform),
            home: const Scaffold(body: RowTitle('a title')),
          ),
        );
        seen.add(
          Theme.of(tester.element(find.byType(RowTitle))).colorScheme.primary,
        );
      }
      expect(seen, hasLength(1));
    });
  });

  group('the text size is the OS setting', () {
    testWidgets('a long title takes two lines and no more, at any size', (
      tester,
    ) async {
      final heights = <double, double>{};
      for (final scale in [1.0, 2.0, 3.2]) {
        await tester.pumpWidget(
          _scaled(
            scale,
            const SizedBox(
              width: 320,
              child: RowTitle(
                'a backlog title long enough that it cannot possibly fit on one line '
                'even before anybody turns their text size up at all',
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'nothing overflowed at $scale',
        );
        expect(tester.widget<Text>(find.byType(Text)).maxLines, 2);
        heights[scale] = tester.getSize(find.byType(Text)).height;
      }

      // The size is the OS setting's to decide: turning it up has to make the text bigger, which
      // a widget that wrote its own size into itself would not do.
      expect(heights[2.0]!, greaterThan(heights[1.0]!));
      expect(heights[3.2]!, greaterThan(heights[2.0]!));
    });
  });

  group('no state is carried by colour alone', () {
    testWidgets('priority says which one it is', (tester) async {
      for (final entry in {
        'high': 'High',
        'medium': 'Med',
        'low': 'Low',
      }.entries) {
        await tester.pumpWidget(_wrap(PriorityMark(entry.key)));
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('a late task says it is late, in words', (tester) async {
      await tester.pumpWidget(_wrap(DueMark('2026-08-07', today: now)));
      expect(find.textContaining('Overdue'), findsOneWidget);

      await tester.pumpWidget(_wrap(DueMark('2026-08-09', today: now)));
      expect(find.text('Due today'), findsOneWidget);
    });

    testWidgets('a state says its name', (tester) async {
      await tester.pumpWidget(_wrap(const StatusMark('in_progress')));
      expect(find.text('In progress'), findsOneWidget);
    });

    test('lateness is decided against the day, not the instant', () {
      expect(isOverdue('2026-08-08', today: now), isTrue);
      expect(isOverdue('2026-08-09', today: now), isFalse);
    });
  });

  group('a row is read as one thing', () {
    test('the sentence carries what the marks show, and no glyphs', () {
      final label = rowLabel(
        words,
        ref: taskRef(2833),
        title: 'wire the store up',
        status: 'in_progress',
        priority: 'medium',
        assigneeKind: 'ai',
        comments: 5,
      );

      expect(label, startsWith('${taskRef(2833)}, '));
      expect(label, contains('In progress'));
      expect(label, contains('Med priority'));
      expect(label, contains('assigned to AI'));
      expect(label, contains('5 comments'));
    });

    test('one comment is not read as "1 comments"', () {
      final label = rowLabel(
        words,
        ref: taskRef(1),
        title: 't',
        status: 'todo',
        comments: 1,
      );
      expect(label, endsWith('1 comment'));

      // Nothing at all when there are none: a row saying "0 comments" spends the listener's
      // attention on the absence of something.
      expect(
        rowLabel(words, ref: taskRef(1), title: 't', status: 'todo'),
        isNot(contains('comment')),
      );
    });

    testWidgets('the marks inside a row say nothing on their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          SpokenAsOne(
            label: 'the whole row',
            child: Row(
              children: [
                const PriorityMark('high'),
                const Expanded(child: RowTitle('wire the store up')),
              ],
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('the whole row'), findsOneWidget);
      expect(find.bySemanticsLabel('High'), findsNothing);
      handle.dispose();
    });
  });

  group('time', () {
    test('it counts while counting helps, then names the day', () {
      expect(
        relativeTime(face, now.subtract(const Duration(seconds: 20)), now: now),
        'just now',
      );
      expect(
        relativeTime(face, now.subtract(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        relativeTime(face, now.subtract(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
      expect(
        relativeTime(face, DateTime(2026, 8, 8, 14, 2), now: now),
        'yesterday 14:02',
      );
      // The month's name and the order it stands in are the language's, not a key's: English
      // writes the month first, and every other sheet gets its own order without translating one.
      expect(relativeTime(face, DateTime(2026, 8, 2), now: now), 'Aug 2');
      expect(relativeTime(face, DateTime(2025, 8, 2), now: now), 'Aug 2, 2025');
    });

    test('"h ago" never outlives the day it was counted from', () {
      // 13 hours back, but on the day before: counting the hours would read as though it were
      // still today.
      expect(
        relativeTime(
          face,
          DateTime(2026, 8, 8, 23, 0),
          now: DateTime(2026, 8, 9, 12, 0),
        ),
        'yesterday 23:00',
      );
      // Forty minutes back and also the day before. Minutes still beat naming the day, because
      // the question being answered is how fresh it is.
      expect(
        relativeTime(
          face,
          DateTime(2026, 8, 8, 23, 50),
          now: DateTime(2026, 8, 9, 0, 30),
        ),
        '40 min ago',
      );
    });

    test('the clock runs the way the phone was set, not the language', () {
      final afternoon = DateTime(2026, 8, 9, 14, 2);
      expect(clockTime(face, afternoon), '14:02');
      // Left alone, it is the language that answers — and English asks for twelve hours. The gap
      // before PM is the narrow one the language's own data asks for, not a plain space.
      expect(clockTime(face12, afternoon), '2:02\u202fPM');
    });

    testWidgets('the exact instant is one long press away', (tester) async {
      await tester.pumpWidget(
        _onA24HourPhone(
          TimeOnHold(
            when: DateTime(2026, 8, 2, 14, 2),
            child: const Text('the row'),
          ),
        ),
      );

      await tester.longPress(find.text('the row'));
      await tester.pumpAndSettle();
      expect(find.text('Aug 2, 2026, 14:02'), findsOneWidget);
    });
  });

  group('a ref is the way back to the PC', () {
    test('it is namespaced, so it still means something off the screen', () {
      // Written in two halves on purpose: a whole ref in a tracked file is what the repository's
      // own lint refuses, since the number resolves in one store and nowhere else.
      expect(taskRef(2833), startsWith('AMB-T-'));
      expect(taskRef(2833), endsWith('2833'));
      expect(decisionRef(31), startsWith('AMB-D-'));
    });

    testWidgets('tapping it copies it and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );

      await tester.pumpWidget(_wrap(RefChip(taskRef(2833))));
      await tester.tap(find.byType(RefChip));
      await tester.pumpAndSettle();

      expect(copied.single, taskRef(2833));
      expect(find.textContaining('Copied'), findsOneWidget);
    });
  });

  group('width, not device', () {
    testWidgets('a narrow screen shows one pane at a time', (tester) async {
      await tester.pumpWidget(
        _sized(
          const Size(400, 800),
          const TwoPane(list: Text('list'), detail: Text('detail')),
        ),
      );
      expect(find.text('list'), findsNothing);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('the split grows, and the page stops where reading does', (
      tester,
    ) async {
      const list = Key('list');
      const detail = Key('detail');
      // The glass itself, not only what the widgets are told about it: the panes are laid out in
      // the space they are actually given.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _sized(
          const Size(1200, 800),
          const TwoPane(
            list: SizedBox.expand(key: list),
            detail: SizedBox.expand(key: detail),
          ),
        ),
      );

      // A share of the glass rather than one width: fixed, everything a wider screen brings lands
      // on one side of the rule.
      expect(
        tester.getSize(find.byKey(list)).width,
        1200 * Layout.listPaneShare,
      );
      // And the side that took the rest stops at a readable measure instead of running the eye
      // off the end of every line.
      expect(tester.getSize(find.byKey(detail)).width, Layout.readable);
    });

    testWidgets(
      'a wide screen shows both, and holds the place when nothing is open',
      (tester) async {
        await tester.pumpWidget(
          _sized(
            const Size(1000, 800),
            const TwoPane(list: Text('list'), detail: Text('detail')),
          ),
        );
        expect(find.text('list'), findsOneWidget);
        expect(find.text('detail'), findsOneWidget);

        await tester.pumpWidget(
          _sized(
            const Size(1000, 800),
            const TwoPane(
              list: Text('list'),
              placeholder: Text('nothing open'),
              detail: null,
            ),
          ),
        );
        expect(find.text('nothing open'), findsOneWidget);
      },
    );

    testWidgets('a page stops where reading does, and sits in the middle', (
      tester,
    ) async {
      const page = Key('page');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _sized(
          const Size(1200, 800),
          const Measured.prose(child: SizedBox.expand(key: page)),
        ),
      );

      expect(tester.getSize(find.byKey(page)).width, Layout.readable);
      // Centred rather than left against the edge: a page pinned to one side of a tablet is read
      // with the head turned.
      expect(
        tester.getTopLeft(find.byKey(page)).dx,
        (1200 - Layout.readable) / 2,
      );
    });

    testWidgets('a page of rows stops sooner than a page of prose', (
      tester,
    ) async {
      const page = Key('page');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _sized(
          const Size(1200, 800),
          const Measured.rows(child: SizedBox.expand(key: page)),
        ),
      );

      // A row is read down its left edge, so the far end of a long line is not where the eye goes.
      expect(tester.getSize(find.byKey(page)).width, Layout.listPaneMax);
    });

    testWidgets('glass narrower than the measure is left alone', (
      tester,
    ) async {
      const page = Key('page');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _sized(
          const Size(360, 800),
          const Measured.prose(child: SizedBox.expand(key: page)),
        ),
      );

      expect(tester.getSize(find.byKey(page)).width, 360);
    });
  });

  testWidgets('the app itself is drawn with this theme', (tester) async {
    // The root asks the phone whether it is paired before it draws anything else.
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      AmenboViewerApp(
        store: BacklogStore.openInMemory(),
        settings: SettingsController(UnkeptSettings()),
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme?.colorScheme.primary,
      viewerTheme(Brightness.light).colorScheme.primary,
    );
    expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
  });

  group('a list is scanned down, not read across', () {
    testWidgets('every title begins where every other title begins', (
      tester,
    ) async {
      final lefts = <double>{};
      for (final priority in [null, 'high', 'low']) {
        await tester.pumpWidget(
          _wrap(
            Row(
              children: [
                RowLead(priority: priority),
                const Expanded(child: RowTitle('a task')),
              ],
            ),
          ),
        );
        lefts.add(tester.getTopLeft(find.byType(RowTitle)).dx);
      }
      // One place, for all three rows: the mark a row happens to wear is not allowed to move the
      // column the eye is following.
      expect(lefts, hasLength(1));
    });

    testWidgets('the priorities in that column differ in shape', (
      tester,
    ) async {
      // They carry no word there, so the shape is what is left when the colour is not seen.
      final shapes = <IconData>{};
      for (final priority in ['high', 'medium', 'low']) {
        await tester.pumpWidget(_wrap(RowLead(priority: priority)));
        shapes.add(tester.widget<Icon>(find.byType(Icon)).icon!);
      }
      expect(shapes, hasLength(3));
    });

    testWidgets('a rule says where the next row starts', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RowSurface(
            onOpen: () {},
            lead: const RowLead(),
            ref: taskRef(2833),
            title: 'a task',
            second: const [],
          ),
        ),
      );
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RowSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final border = (decorated.decoration as BoxDecoration).border as Border;
      expect(border.bottom.width, Stroke.rule);
      expect(border.bottom.color, lightPalette.border);
    });

    testWidgets('a row opens with the number it is called by on the PC', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: TaskRow(
              line: _line(title: 'wire the store up'),
              today: now,
              onOpen: () {},
            ),
          ),
        ),
      );

      // One text rather than two, so a title that wraps comes back to the edge the number
      // started at, and every other title in the list starts there too.
      expect(find.text('${taskRef(1)} wire the store up'), findsOneWidget);
      // And nothing in the row to aim at: what a tap on it opens is the row.
      expect(find.byType(RefChip), findsNothing);
    });

    testWidgets('what is under a title is ranked, not enumerated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: TaskRow(
              line: _line(
                title: 'wire the store up',
                priority: 'high',
                blockedBy: 2833,
                comments: 3,
              ),
              today: now,
              projectName: 'Amenbo',
              onOpen: () {},
            ),
          ),
        ),
      );

      // No dot between the parts, and the one that decides whether to open the row is bigger and
      // darker than the context beside it.
      expect(find.text('·'), findsNothing);
      final reason = tester.widget<Text>(
        find.textContaining('is not finished'),
      );
      final project = tester.widget<Text>(find.text('Amenbo'));
      expect(reason.style!.fontSize!, greaterThan(project.style!.fontSize!));
      expect(reason.style!.color, isNot(project.style!.color));
    });

    testWidgets('a heading does not read weaker than the rows under it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              ListHeading(title: 'Stalled'),
              RowTitle('a task'),
            ],
          ),
        ),
      );
      final heading = tester.widget<Text>(find.text('Stalled')).style!;
      final title = tester.widget<Text>(find.text('a task')).style!;
      expect(heading.fontSize!, greaterThanOrEqualTo(title.fontSize!));
      expect(heading.fontWeight!.value, greaterThan(title.fontWeight!.value));
    });
  });

  group('nothing pressable is smaller than a finger', () {
    /// What the finger actually has to land on: the box the tap is answered in, which is not the
    /// same box as the text inside it.
    Size pressed(WidgetTester tester, Type inside) => tester.getSize(
      find
          .descendant(of: find.byType(inside), matching: find.byType(InkWell))
          .first,
    );

    testWidgets('the ref is a target, and still drawn as a label', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(RefChip(taskRef(2833))));

      expect(
        pressed(tester, RefChip).height,
        greaterThanOrEqualTo(Layout.touch),
      );
      // The point of growing the area rather than the number: it is read as the quiet address on
      // the bar, and hit as something a thumb can find.
      expect(
        tester.getSize(find.text(taskRef(2833))).height,
        lessThan(Layout.touch),
      );
    });

    testWidgets('a row with nothing under its title is still a target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: RowSurface(
              onOpen: () {},
              lead: const RowLead(),
              ref: taskRef(2833),
              title: 'a task',
              second: const [],
            ),
          ),
        ),
      );

      expect(
        pressed(tester, RowSurface).height,
        greaterThanOrEqualTo(Layout.touch),
      );
    });

    testWidgets('the project on a head is one too', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: DetailHead(
              title: 'wire the store up',
              marks: const [],
              project: 'Amenbo',
              onProject: () {},
            ),
          ),
        ),
      );

      expect(
        pressed(tester, DetailHead).height,
        greaterThanOrEqualTo(Layout.touch),
      );
    });
  });
}

TaskLine _line({
  required String title,
  String status = 'todo',
  String? priority,
  int? blockedBy,
  int comments = 0,
}) => TaskLine(
  id: 1,
  projectId: 1,
  title: title,
  status: status,
  priority: priority,
  assigneeKind: null,
  draft: false,
  dueOn: null,
  startOn: null,
  updatedAt: '2026-08-09T00:00:00Z',
  closedAt: null,
  comments: comments,
  blockedBy: blockedBy,
  undecided: null,
  excerpt: null,
  matchedIn: null,
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: Words.localizationsDelegates,
  supportedLocales: Words.supportedLocales,
  theme: viewerTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

/// A phone whose owner set a 24-hour clock. Said out loud, because the default a test would
/// otherwise get is not a decision anybody made.
Widget _onA24HourPhone(Widget child) => MaterialApp(
  localizationsDelegates: Words.localizationsDelegates,
  supportedLocales: Words.supportedLocales,
  theme: viewerTheme(Brightness.light),
  home: MediaQuery(
    data: const MediaQueryData(alwaysUse24HourFormat: true),
    child: Scaffold(body: Center(child: child)),
  ),
);

Widget _scaled(double scale, Widget child) => MaterialApp(
  localizationsDelegates: Words.localizationsDelegates,
  supportedLocales: Words.supportedLocales,
  theme: viewerTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

/// A window of exactly [size]. `home:` is laid out tight to the test surface, so the box has to
/// sit under something that hands down loose constraints or it silently keeps the surface's own
/// width — which is the one thing these tests are about.
Widget _sized(Size size, Widget child) => MaterialApp(
  localizationsDelegates: Words.localizationsDelegates,
  supportedLocales: Words.supportedLocales,
  theme: viewerTheme(Brightness.light),
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox.fromSize(
      size: size,
      child: Scaffold(body: child),
    ),
  ),
);
