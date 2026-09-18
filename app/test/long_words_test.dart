// Every screen, drawn in the languages that write the longest words.
//
// The layout was set in English, and English is short. "Done" is four letters where German asks
// for "Abgeschlossen", Russian for "Завершено" and Polish for "Zakończone"; "Settings" is one word
// where German wants "Einstellungen öffnen" on a button. A width that held in the language the app
// was written in is not a width that holds, and the place it stops holding is the narrowest phone
// still in use with its text turned up.
//
// So the three longest of the nineteen are drawn here, on that phone, at three text sizes.
// Nothing is asserted about how it looks: a line that runs off the edge reports itself, because a
// `RenderFlex overflowed` is an exception and an exception fails the test it was thrown in. What
// this file buys is that somebody has to be looking — a screenshot in German is something a person
// remembers to take, and this is not.
//
// **The bar here is higher than any phone.** A widget test draws in a font whose every glyph is a
// full square, so a word of ten letters is ten ems wide where a real face would set it in five or
// six. Everything below therefore fits with room to spare on a real screen, and that headroom is
// the point: the width a translator's word will want is not knowable from here.
//
// **It does not catch a line that merely reads badly.** Text that wraps to four lines, or is cut
// off with an ellipsis, is inside its box and passes here. Those are read on a phone; this holds
// the floor under them.

import 'package:amenbo_viewer/about_screen.dart';
import 'package:amenbo_viewer/build_origin.dart';
import 'package:amenbo_viewer/cloudflare_intake.dart';
import 'package:amenbo_viewer/connection.dart';
import 'package:amenbo_viewer/connection_screen.dart';
import 'package:amenbo_viewer/decision_detail.dart';
import 'package:amenbo_viewer/first_sync.dart';
import 'package:amenbo_viewer/home.dart';
import 'package:amenbo_viewer/l10n/words.dart';
import 'package:amenbo_viewer/pairing_guide.dart';
import 'package:amenbo_viewer/pairing_scan.dart';
import 'package:amenbo_viewer/settings.dart';
import 'package:amenbo_viewer/settings_screen.dart';
import 'package:amenbo_viewer/state_band.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:amenbo_viewer/task_detail.dart';
import 'package:amenbo_viewer/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backlog_fixture.dart';

/// The three of the nineteen that break an English layout first.
///
/// German compounds, so its nouns are single unbreakable words; Russian is Cyrillic and long with
/// it; Polish is the longest of the Latin sheets. A layout that survives the three survives the
/// rest — the other sixteen are shorter than at least one of them nearly everywhere.
const _longLanguages = [Locale('de'), Locale('ru'), Locale('pl')];

/// The narrowest glass this is expected to be read on.
///
/// 320 points is the small iPhone and the cheap Android, and it is where the app is judged: a
/// screen that fits at 320 fits everything above it, and nothing below it is being sold.
const _narrow = Size(320, 640);

/// The text sizes to draw each screen at.
///
/// The phone as it comes; the phone of somebody who turned the text up a notch; and 200%, which is
/// as far as Android's own slider goes and past where iOS stops before its accessibility sizes.
/// This is where most of what breaks, breaks: the width a word wants grows with the text and the
/// glass does not.
const _textSizes = <String, TextScaler>{
  'as it comes': TextScaler.noScaling,
  'text turned up': TextScaler.linear(1.3),
  'text at the far end': TextScaler.linear(2.0),
};

final _today = DateTime(2026, 8, 9, 12);

/// A phone pointed at a Worker, with a round behind it — the connection screen with every line it
/// has to say filled in.
final _paired = Connection(
  paired: true,
  host: 'amenbo.example.workers.dev',
  lastTaken: LastTaken(
    at: _today.subtract(const Duration(minutes: 12)),
    version: 91,
    seq: 4207,
    specVersion: 1,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BacklogStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    store = BacklogStore.openInMemory();
  });
  tearDown(() => store.close());

  /// A backlog with one of everything a screen can draw, so no widget is skipped for want of a
  /// row to put in it.
  void fill() {
    store.applyPage([
      BacklogChange.put('project', 16, project(id: 16, name: 'viewer')),
      BacklogChange.put('project', 17, project(id: 17, name: 'plugin')),
      BacklogChange.put(
        'task',
        1,
        task(
          id: 1,
          title: 'よむ',
          notes: 'ほんぶん',
          status: 'in_progress',
          priority: 'high',
          assigneeKind: 'ai',
          dueOn: '2026-08-01',
        ),
      ),
      BacklogChange.put(
        'task',
        2,
        task(id: 2, title: 'まつ', status: 'blocked', priority: 'medium'),
      ),
      BacklogChange.put(
        'task',
        3,
        task(id: 3, title: 'おわった', status: 'done', priority: 'low'),
      ),
      BacklogChange.put(
        'task',
        4,
        task(id: 4, title: 'これから', startOn: '2026-12-01', projectId: 17),
      ),
      BacklogChange.put(
        'task_dependency',
        1,
        dependency(id: 1, taskId: 2, blockedById: 1),
      ),
      BacklogChange.put('task_comment', 1, comment(id: 1, taskId: 1)),
      BacklogChange.put(
        'decision',
        1,
        decision(id: 1, title: 'きめた', body: 'りゆう'),
      ),
      BacklogChange.put(
        'decision_comment',
        1,
        decisionComment(id: 1, decisionId: 1),
      ),
      BacklogChange.put(
        'decision_task_link',
        1,
        decisionLink(id: 1, decisionId: 1, taskId: 1),
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
        taskDimensionValue(id: 1, taskId: 1, dimensionId: 1, valueId: 1),
      ),
      BacklogChange.put('task_commit', 1, taskCommit(id: 1, taskId: 1)),
      BacklogChange.put('attachment', 1, attachment(id: 1, targetId: 1)),
    ]);
    store.setMeta(MetaKey.fetchedAt, '2026-08-09T03:00:00Z');
  }

  /// Draws one screen on the narrow phone, in one language, at one text size.
  ///
  /// The window is set as well as the `MediaQuery`: a screen told it is 320 wide while being laid
  /// out on the binding's default surface is a screen that never runs out of room.
  Future<void> draw(
    WidgetTester tester,
    Widget screen, {
    required Locale locale,
    required TextScaler text,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _narrow;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: Words.localizationsDelegates,
        supportedLocales: Words.supportedLocales,
        theme: viewerTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(size: _narrow, textScaler: text),
          child: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget viewer() => ViewerHome(
    store: store,
    settings: SettingsController(UnkeptSettings()),
    appName: 'Amenbo Viewer',
    clock: () => _today,
    rounds: (pairing) =>
        (watching) async => const IntakeReport(
          records: 0,
          pages: 0,
          seq: 0,
          startedOver: false,
        ),
  );

  for (final locale in _longLanguages) {
    group(locale.languageCode, () {
      for (final size in _textSizes.entries) {
        group(size.key, () {
          final text = size.value;

          testWidgets('the guide a phone with no way in opens on', (
            tester,
          ) async {
            await draw(
              tester,
              PairingGuideScreen(appName: 'Amenbo Viewer', onPaired: (_) {}),
              locale: locale,
              text: text,
            );
          });

          testWidgets('the camera, before it is asked for and after a no', (
            tester,
          ) async {
            final camera = _NoCamera();
            await draw(
              tester,
              PairingScanScreen(camera: camera),
              locale: locale,
              text: text,
            );
            final onward = find.text(lookupWords(locale).pairContinue);
            await tester.dragUntilVisible(
              onward,
              find.byType(ListView),
              const Offset(0, -100),
            );
            await tester.tap(onward);
            await tester.pumpAndSettle();
          });

          testWidgets('the first round, and where it stopped', (tester) async {
            await draw(
              tester,
              const FirstSyncScreen(take: _cannotReachIt),
              locale: locale,
              text: text,
            );
          });

          testWidgets('the four states, and the rows under them', (
            tester,
          ) async {
            fill();
            await draw(tester, viewer(), locale: locale, text: text);

            // Swiped rather than tapped: the switch scrolls sideways once the names are long, so
            // the last of the four is off the edge of a 320-wide phone in every one of these
            // languages — which is what a scrolling switch is for.
            for (var state = 1; state < 4; state += 1) {
              await tester.drag(
                find.byType(TabBarView),
                Offset(-_narrow.width, 0),
              );
              await tester.pumpAndSettle();
            }
          });

          testWidgets('the decisions, and the search', (tester) async {
            fill();
            await draw(tester, viewer(), locale: locale, text: text);
            final words = lookupWords(locale);

            await tester.tap(find.text(words.tabDecisions));
            await tester.pumpAndSettle();

            await tester.tap(find.text(words.tabSearch));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), 'よむ');
            await tester.pumpAndSettle();
          });

          testWidgets('a task read to the end', (tester) async {
            fill();
            await draw(
              tester,
              TaskDetailScreen(
                store: store,
                taskId: 2,
                projectName: 'viewer',
                onProject: (_) {},
                onOpenTask: (_) {},
                onOpenDecision: (_) {},
                onShare: (_) async {},
                clock: () => _today,
              ),
              locale: locale,
              text: text,
            );
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pumpAndSettle();
          });

          testWidgets('a decision read to the end', (tester) async {
            fill();
            await draw(
              tester,
              DecisionDetailScreen(
                store: store,
                decisionId: 1,
                projectName: 'viewer',
                onProject: (_) {},
                onOpenTask: (_) {},
                onOpenDecision: (_) {},
                onShare: (_) async {},
                clock: () => _today,
              ),
              locale: locale,
              text: text,
            );
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pumpAndSettle();
          });

          testWidgets('the settings, read to the bottom', (tester) async {
            await draw(
              tester,
              SettingsScreen(
                settings: SettingsController(UnkeptSettings()),
                connection: _Facts(_paired),
                appName: 'Amenbo Viewer',
              ),
              locale: locale,
              text: text,
            );
            // The two ways out sit under the choices, which is off the bottom of this phone as
            // soon as the text grows.
            await tester.dragUntilVisible(
              find.text(lookupWords(locale).aboutTitle),
              find.byType(ListView),
              const Offset(0, -100),
            );
          });

          testWidgets('what this phone is connected to', (tester) async {
            await draw(
              tester,
              ConnectionScreen(facts: _Facts(_paired)),
              locale: locale,
              text: text,
            );
          });

          // Once per origin: each is a sentence of its own, and the longest of them is the one
          // that has to say Play cannot separate the listing from a testing track.
          for (final origin in BuildOrigin.values) {
            testWidgets('what this build is, from ${origin.name}', (
              tester,
            ) async {
              await draw(
                tester,
                AboutScreen(
                  appName: 'Amenbo Viewer',
                  readOrigin: () async => origin,
                ),
                locale: locale,
                text: text,
              );
            });
          }

          for (final standing in Standing.values) {
            if (standing == Standing.quiet) continue;

            testWidgets('the band saying ${standing.name}', (tester) async {
              // Both shapes: the strip over a picture, and the same words taking a device that has
              // never had anything.
              await draw(
                tester,
                Scaffold(
                  body: ListView(
                    children: [
                      StateBand(standing: standing, onPairAgain: () {}),
                      StateBand(
                        standing: standing,
                        onPairAgain: () {},
                        whole: true,
                      ),
                    ],
                  ),
                ),
                locale: locale,
                text: text,
              );
            });
          }
        });
      }
    });
  }
}

/// A round that gets nowhere, so the first-sync screen draws what it says when one stops — which
/// is the half of that screen with a button on it.
Future<IntakeReport> _cannotReachIt(void Function(IntakeProgress) watching) =>
    Future.error(const IntakeException(IntakeFailure.unreachable));

/// A phone whose owner said no to the camera.
class _NoCamera implements Camera {
  @override
  Future<CameraAccess> ask() async => CameraAccess.refused;

  @override
  Future<void> openTheSettings() async {}

  @override
  Widget view(void Function(String text) onCode) =>
      const ColoredBox(color: Colors.black);
}

/// A connection the screen can read without a phone under it.
class _Facts implements ConnectionFacts {
  _Facts(this.connection);

  final Connection connection;

  @override
  Future<Connection> read() async => connection;

  @override
  Future<void> erase() async {}
}
