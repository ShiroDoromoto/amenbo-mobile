// The root: which screen a phone opens on, and where the ways out of the three tabs lead.
//
// Every screen below this was built to be handed what it needs and to hand back what was pressed.
// What is checked here is only the joining — that the guide gives way once there is a way in, that
// a bundle's remainder and a number on the card arrive at the one list face carrying what was
// pressed, and that a task opens beside the list when there is width for it.

import 'dart:async';

import 'package:amenbo_viewer/cloudflare_intake.dart';
import 'package:amenbo_viewer/decision_detail.dart';
import 'package:amenbo_viewer/decisions_screen.dart';
import 'package:amenbo_viewer/first_sync.dart';
import 'package:amenbo_viewer/home.dart';
import 'package:amenbo_viewer/now_screen.dart';
import 'package:amenbo_viewer/pairing_guide.dart';
import 'package:amenbo_viewer/pairing_store.dart';
import 'package:amenbo_viewer/search_screen.dart';
import 'package:amenbo_viewer/settings.dart';
import 'package:amenbo_viewer/settings_screen.dart';
import 'package:amenbo_viewer/state_band.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/task_detail.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:amenbo_viewer/ui/two_pane.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';
import 'words_fixture.dart';

final today = DateTime(2026, 8, 9, 12);

final aPairing = Pairing(
  url: Uri.parse('https://amenbo.example.workers.dev'),
  readToken: 'cmVhZC10b2tlbg',
  encryptionKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
);

/// A round that lands nothing and says so, so the first sync finishes without a network.
TakeTheBacklog nothingToTake(Pairing pairing) => (watching) async {
  watching(const IntakeProgress(records: 0, seq: 0, target: 0));
  return const IntakeReport(records: 0, pages: 0, seq: 0, startedOver: false);
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BacklogStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // The first sync buzzes once before it gets out of the way, and waits on the answer. Nothing
    // answers a channel with no engine behind it, so the phone's side is stood in for.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    store = BacklogStore.openInMemory();
  });
  tearDown(() => store.close());

  /// Gives the test the glass it says it has.
  ///
  /// `MediaQuery` alone only tells the widgets what to think; the surface they are laid out on
  /// stays whatever the test binding started with. That was harmless while nothing between the
  /// window and the panes took any width — a rail down the side takes some, and a screen that
  /// claims to be a tablet while being laid out on a phone splits where neither would.
  void glass(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget home({
    Size size = const Size(400, 800),
    Rounds? rounds,
    SettingsController? settings,
  }) => MaterialApp(
    localizationsDelegates: Words.localizationsDelegates,
    supportedLocales: Words.supportedLocales,
    theme: viewerTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: ViewerHome(
        store: store,
        settings: settings ?? SettingsController(UnkeptSettings()),
        appName: 'Amenbo Viewer',
        clock: () => today,
        rounds: rounds ?? nothingToTake,
      ),
    ),
  );

  /// Settings as this phone left them, with the one choice this group is about already made.
  SettingsController asked(Refresh refresh) =>
      SettingsController(UnkeptSettings())..setRefresh(refresh);

  group('what the app opens on', () {
    testWidgets('a phone with no way in is told how to make one', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.byType(PairingGuideScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a paired phone is shown its backlog', (tester) async {
      await const PairingStore().save(aPairing);
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(PairingGuideScreen), findsNothing);
    });

    testWidgets('rows are worth showing even with no pairing behind them', (
      tester,
    ) async {
      // A phone whose rows came in over a route this build no longer has. The guide would hide
      // what is on the device to say something the band says over the top of it.
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('a code that read goes straight into the first round', (
      tester,
    ) async {
      var rounds = 0;
      // Held open, so the wait can be looked at before it ends.
      final round = Completer<IntakeReport>();
      await tester.pumpWidget(
        home(
          rounds: (pairing) => (watching) {
            rounds += 1;
            return round.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      // What the guide hands up, as the camera would have handed it.
      final guide = tester.widget<PairingGuideScreen>(
        find.byType(PairingGuideScreen),
      );
      guide.onPaired(aPairing);
      // Pumped rather than settled: the bar on the first sync turns for as long as the round
      // lasts, and a round that has not answered never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(rounds, 1);
      expect(find.byType(FirstSyncScreen), findsOneWidget);

      round.complete(
        const IntakeReport(records: 2, pages: 1, seq: 2, startedOver: false),
      );
      await tester.pumpAndSettle();

      // And it comes out on the backlog, not on a screen congratulating anyone.
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(FirstSyncScreen), findsNothing);
    });

    testWidgets('what the first round brought is on the screen it lands on', (
      tester,
    ) async {
      final round = Completer<IntakeReport>();
      await tester.pumpWidget(
        home(
          rounds: (pairing) =>
              (watching) => round.future,
        ),
      );
      await tester.pumpAndSettle();

      tester
          .widget<PairingGuideScreen>(find.byType(PairingGuideScreen))
          .onPaired(aPairing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The front screen is built behind the wait, against a store that is still empty — so the
      // rows this round writes are ones it has already read past.
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'はじめてとどいた')),
      ]);
      round.complete(
        const IntakeReport(records: 1, pages: 1, seq: 1, startedOver: false),
      );
      await tester.pumpAndSettle();

      // Not "nothing has arrived yet", and not behind a pill either: this is the backlog the
      // person just watched arrive.
      expect(taskRowTitled(1, 'はじめてとどいた'), findsOneWidget);
      expect(find.textContaining('New activity'), findsNothing);
    });
  });

  group('the three tabs', () {
    setUp(() async {
      await const PairingStore().save(aPairing);
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'いちばんのしごと')),
      ]);
    });

    testWidgets('the app opens on the front screen', (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.byType(NowScreen), findsOneWidget);
      expect(find.text(words.tabTasks), findsOneWidget);
      expect(find.text(words.tabDecisions), findsOneWidget);
      expect(find.text(words.tabSearch), findsOneWidget);
      // The bottom bar is the thumb's, and it is spent on the three things read every day.
      expect(find.byType(NavigationDestination), findsNWidgets(3));
    });

    testWidgets('each destination is one press away', (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      await tester.tap(find.text(words.tabDecisions));
      await tester.pumpAndSettle();
      expect(find.byType(DecisionsScreen), findsOneWidget);

      await tester.tap(find.text(words.tabSearch));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('the decisions are read off the store on arriving at them', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      // Landed while the front screen was being read — the shell built the decisions face against
      // a store that did not have this yet.
      store.applyPage([
        BacklogChange.put('decision', 1, decision(id: 1, title: 'あとからきめた')),
      ]);

      await tester.tap(find.text(words.tabDecisions));
      await tester.pumpAndSettle();

      expect(decisionRowTitled(1, 'あとからきめた'), findsOneWidget);
    });

    testWidgets('a decision opens on top, whatever the width', (tester) async {
      const wide = Size(1000, 800);
      glass(tester, wide);
      store.applyPage([
        BacklogChange.put('decision', 1, decision(id: 1, title: 'ひらくきめごと')),
      ]);

      await tester.pumpWidget(home(size: wide));
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.tabDecisions));
      await tester.pumpAndSettle();
      await tester.tap(decisionRowTitled(1, 'ひらくきめごと'));
      await tester.pumpAndSettle();

      // Pushed rather than swapped in beside the list: what a decision is opened from is a detail
      // as often as a list, and the way back has to be the same one every time.
      expect(find.byType(DecisionDetailScreen), findsOneWidget);
      expect(find.byType(DecisionsScreen), findsNothing);
    });

    testWidgets('a wide screen puts the three down the side instead', (
      tester,
    ) async {
      const wide = Size(1000, 800);
      glass(tester, wide);
      await tester.pumpWidget(home(size: wide));
      await tester.pumpAndSettle();

      // The bottom edge is the furthest point on glass nobody is holding one-handed, so the three
      // move to the side — and they are still the same three, named.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text(words.tabTasks), findsOneWidget);
      expect(find.text(words.tabDecisions), findsOneWidget);
      expect(find.text(words.tabSearch), findsOneWidget);

      await tester.tap(find.text(words.tabSearch));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('the decisions are marked by the gavel the desk uses', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      // The same mark as the decisions screen on the desk. Somebody reads both in one day, and
      // two different marks for one thing is two things to them.
      expect(find.byIcon(Icons.gavel_outlined), findsOneWidget);

      await tester.tap(find.text(words.tabDecisions));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.gavel), findsOneWidget);
    });

    testWidgets('a phone keeps them under the thumb', (tester) async {
      const narrow = Size(400, 800);
      glass(tester, narrow);
      await tester.pumpWidget(home(size: narrow));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('the settings are opened from any of the three, not a tab', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      // The same corner on all three, so reading a decision and wanting the settings is not a
      // reason to go back to the front screen first.
      for (final tab in [words.tabTasks, words.tabDecisions, words.tabSearch]) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(words.settingsTitle));
        await tester.pumpAndSettle();

        // Pushed, so the way back is the one every other pushed screen has.
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // And it came back to the tab it was opened from, not to the front screen.
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('search starts from everything, every time it is arrived at', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      await tester.tap(find.text(words.tabSearch));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'のこらない');
      await tester.pumpAndSettle();

      await tester.tap(find.text(words.tabTasks));
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.tabSearch));
      await tester.pumpAndSettle();

      // A word left behind on the way out would narrow a screen the person came to fresh.
      expect(find.text('のこらない'), findsNothing);
    });
  });

  group('where a list leads', () {
    setUp(() async {
      await const PairingStore().save(aPairing);
      store.applyPage([
        for (var id = 1; id <= 3; id++)
          BacklogChange.put('task', id, task(id: id, title: 'しごと $id')),
      ]);
    });

    testWidgets('a row opens the task it names', (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      await tester.tap(taskRowTitled(1, 'しごと 1'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailScreen), findsOneWidget);
    });

    testWidgets('with width for two, what is opened sits beside the list', (
      tester,
    ) async {
      const wide = Size(1000, 800);
      glass(tester, wide);
      await tester.pumpWidget(home(size: wide));
      await tester.pumpAndSettle();

      expect(find.byType(TwoPane), findsWidgets);
      await tester.tap(taskRowTitled(1, 'しごと 1'));
      await tester.pumpAndSettle();

      // Beside it, not on top of it: the list is still there to go on reading.
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      expect(find.byType(NowScreen), findsOneWidget);
    });
  });

  group('when it goes and looks', () {
    setUp(() async {
      await const PairingStore().save(aPairing);
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);
    });

    /// A round that counts its callers and lands one record.
    ({List<int> ran, Rounds rounds}) counted() {
      final ran = <int>[];
      return (
        ran: ran,
        rounds: (pairing) => (watching) async {
          ran.add(ran.length);
          // A different row each round, so which round put it there is readable.
          final id = 2 + ran.length;
          store.applyPage([
            BacklogChange.put(
              'task',
              id,
              task(
                id: id,
                title: 'とどいた $id',
                // Stamped by the PC, and later each round: what arrived while the screen was
                // being read is decided by comparing these.
                updatedAt: '2026-08-09T11:0${ran.length}:00Z',
              ),
            ),
          ]);
          return const IntakeReport(
            records: 1,
            pages: 1,
            seq: 2,
            startedOver: false,
          );
        },
      );
    }

    testWidgets('automatically means the launch', (tester) async {
      final round = counted();
      await tester.pumpWidget(
        home(rounds: round.rounds, settings: asked(Refresh.automatic)),
      );
      await tester.pumpAndSettle();

      expect(round.ran, hasLength(1));
    });

    testWidgets('and the return to the front', (tester) async {
      final round = counted();
      await tester.pumpWidget(
        home(rounds: round.rounds, settings: asked(Refresh.automatic)),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(round.ran, hasLength(2));
    });

    testWidgets('only when I pull means neither of them', (tester) async {
      final round = counted();
      await tester.pumpWidget(
        home(rounds: round.rounds, settings: asked(Refresh.manualOnly)),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(round.ran, isEmpty);

      // The thumb still fetches: what the setting turns off is the app going on its own.
      await tester.tap(find.byTooltip(words.refresh));
      await tester.pumpAndSettle();
      expect(round.ran, hasLength(1));
    });

    testWidgets('what a round nobody asked for brought back waits', (
      tester,
    ) async {
      final round = counted();
      await tester.pumpWidget(
        home(rounds: round.rounds, settings: asked(Refresh.automatic)),
      );
      await tester.pumpAndSettle();
      // The launch round landed before there was anything to interrupt.
      expect(taskRowTitled(3, 'とどいた 3'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // This one arrived under someone already reading, so it is counted, not applied.
      expect(taskRowTitled(4, 'とどいた 4'), findsNothing);
      expect(find.textContaining('New activity'), findsOneWidget);

      await tester.tap(find.textContaining('New activity'));
      await tester.pumpAndSettle();
      expect(taskRowTitled(4, 'とどいた 4'), findsOneWidget);
    });
  });

  group('rows with no pairing behind them', () {
    setUp(() {
      // Rows taken over a route this build no longer has, and nothing this phone can ask.
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);
    });

    testWidgets('the band says so, over the rows rather than instead of them', (
      tester,
    ) async {
      await tester.pumpWidget(home(settings: asked(Refresh.automatic)));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(
        find.text(standingWords(words, Standing.unpaired)),
        findsOneWidget,
      );
      // Not "nothing has arrived yet": something did arrive, and the reason no more is coming
      // is the thing worth saying.
      expect(find.text(standingWords(words, Standing.waiting)), findsNothing);
    });

    testWidgets('no round is taken and no pull is offered', (tester) async {
      await tester.pumpWidget(home(settings: asked(Refresh.automatic)));
      await tester.pumpAndSettle();

      // A pull that silently did nothing would be worse than a list that does not offer one.
      expect(find.byTooltip(words.refresh), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byTooltip(words.refresh), findsNothing);
    });
  });
}
