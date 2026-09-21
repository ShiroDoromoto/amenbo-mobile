/// "Tasks" — the four states, one at a time.
///
/// This is the screen the app is opened for, and what it is asked is nearly always one of four
/// questions: what is being worked on, what is stuck, what is next, what got finished. So the
/// screen is divided the way the backlog itself is — by Amenbo's own status — and the person moves
/// between the four rather than scrolling past them. The same four they read on the PC, in the
/// same words, so there is nothing to learn twice.
///
/// Four rules shape everything below.
///
/// * **Divided by state, not by whether it can be started.** Whether a task's premises are met is
///   derived, and it changes overnight without the task moving. A row waiting on something stays
///   in `todo` and says what it is waiting on.
/// * **One state is read to its end.** A window at a time, asked for by reaching the bottom —
///   there is no "N more" that hands the rest to another screen. Finished work is all of it,
///   newest first, with the date written in wherever it changes: the device holds the whole copy,
///   so a cut-off would be hiding rows that are already here.
/// * **The floor is never swapped while someone is standing on it.** Rows that arrive on their own
///   are counted, not applied — the person presses a pill when they are ready. The exception is a
///   list that is still empty, where there is nothing to pull out from under anyone and a first
///   sync should be seen filling up.
/// * **Projects narrow, they do not divide.** Everything the machine sends is stacked together by
///   default, because "what moved overnight" is not a question anybody asks one project at a time.
/// * **The top is one line.** When the picture was taken, and the way to take a newer one. It is
///   the first thing the eye lands on, and what the person came to read is under it.
library;

import 'package:flutter/material.dart';

import 'cloudflare_intake.dart';
import 'l10n/words.dart';
import 'state_band.dart';
import 'store/backlog_queries.dart';
import 'store/backlog_store.dart';
import 'ui/project_choice.dart';
import 'ui/task_row.dart';
import 'ui/theme.dart';
import 'ui/time.dart';
import 'ui/tokens.dart';
import 'ui/touch.dart';

/// What the switch calls each state.
///
/// Amenbo's own words, and the same ones a row wears — a switch named one thing holding rows
/// marked another would be two names for one fact. The closed one is said as "done" because that
/// is what nearly all of it is; a rejected row says so on itself.
String stateHeading(Words words, TaskState state) => switch (state) {
  TaskState.todo => words.statusTodo,
  TaskState.inProgress => words.statusInProgress,
  TaskState.blocked => words.statusBlocked,
  TaskState.finished => words.statusDone,
};

/// Says that rows arrived. Nothing about which — the screen that cares reads the store itself.
///
/// [watched] is the one thing it carries, because it decides whether the floor may be swapped.
/// Rows that landed behind someone's back are offered behind a pill; rows the person sat and
/// watched land — the first sync — are what they are here to read, and holding those back would
/// be offering them what they just finished waiting for.
class Arrivals extends ChangeNotifier {
  bool _watched = false;

  /// Whether the last lot were watched arriving.
  bool get watched => _watched;

  void tick({bool watched = false}) {
    _watched = watched;
    notifyListeners();
  }
}

class NowScreen extends StatefulWidget {
  const NowScreen({
    super.key,
    required this.store,
    required this.onOpen,
    this.failure,
    this.paired = true,
    this.onPairAgain,
    this.onOpenSettings,
    this.take,
    this.arrivals,
    this.clock = DateTime.now,
  });

  final BacklogStore store;

  /// Opening a row.
  final void Function(TaskLine line) onOpen;

  /// How the last round of the intake ended, or null where it did not fail. It decides the band
  /// at the top; it never decides whether the list is drawn.
  final IntakeFailure? failure;

  /// Whether this phone has a pairing. It decides the band and nothing else — rows already here
  /// are drawn whether or not anything is still adding to them.
  final bool paired;

  final VoidCallback? onPairAgain;
  final VoidCallback? onOpenSettings;

  /// Goes and fetches. Null where there is nothing to ask — the screen still draws what is on the
  /// device, which is the whole point of it being a local store.
  final Future<void> Function()? take;

  /// Ticks when a fetch this screen did not run has written rows.
  final Arrivals? arrivals;

  /// Passed in rather than read here, so a row and the heading over it cannot disagree about what
  /// "today" was.
  final DateTime Function() clock;

  /// One state on the switch: its name, and how many are in it.
  static String tab(Words words, TaskState state, Counted count) =>
      labelWithCount(words, stateHeading(words, state), count);

  static String arrived(Words words, Counted count) =>
      words.newActivity(countLabel(words, count));

  /// The clock, not "3 h ago".
  ///
  /// This is the one place the app spells a time out. What the person is judging here is how old
  /// what they are reading is, and a phone whose clock is wrong can still say the hour it took
  /// something at — where "3 h ago" would be wrong by exactly the amount the clock is out.
  ///
  /// The day comes with it once it is not today's. This line is the only thing a phone with no
  /// signal has to date what it is reading by, and out of signal is exactly where a picture stops
  /// being hours old and starts being days old.
  static String takenAt(
    TimeFace face,
    DateTime when, {
    required DateTime now,
  }) => face.words.takenAt(clockOnDay(face, when, now: now));

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen>
    with SingleTickerProviderStateMixin {
  /// Built here rather than lazily beside its declaration: a screen taken down before it ever
  /// drew the switch — a phone with nothing on it — would otherwise create the controller inside
  /// `dispose`, which is the one place it cannot be created.
  late final TabController _tabs;

  /// Null is every project at once, and it is where the screen starts. Narrowing is a state of
  /// the screen, not a setting — coming back tomorrow shows everything again.
  int? _projectId;

  var _projects = const <({int id, String name})>[];
  var _names = const <int, String>{};

  /// What each state holds: the windows read so far, how many there are in all, and whether the
  /// last window came back full. A full window is the only honest sign that there is more.
  final _rows = <TaskState, List<TaskLine>>{};
  final _totals = <TaskState, Counted>{};
  final _more = <TaskState, bool>{};
  bool _widening = false;

  /// The newest change the drawn rows include, stamped by the PC. What arrived after it is what
  /// the pill offers.
  String? _drawnAt;

  /// When the last round finished. It is what says how old the picture is, which is the one thing
  /// a reader offline has to be told and the one thing nothing else on the screen says.
  DateTime? _takenAt;

  /// What has arrived since [_drawnAt], waiting to be let in. Null while nothing has.
  Counted? _arrived;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: TaskState.values.length, vsync: this);
    _load();
    widget.arrivals?.addListener(_rowsArrived);
  }

  @override
  void didUpdateWidget(NowScreen old) {
    super.didUpdateWidget(old);
    if (old.arrivals != widget.arrivals) {
      old.arrivals?.removeListener(_rowsArrived);
      widget.arrivals?.addListener(_rowsArrived);
    }
  }

  @override
  void dispose() {
    widget.arrivals?.removeListener(_rowsArrived);
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    final today = widget.clock();
    _projects = widget.store.projects();
    _names = {for (final project in _projects) project.id: project.name};
    // A project can go away — archived on the PC, or gone from the place entirely — and the
    // narrowing it held has to let go rather than showing an empty list forever.
    if (_projectId != null && !_names.containsKey(_projectId)) {
      _projectId = null;
    }
    for (final state in TaskState.values) {
      final rows = widget.store.inState(
        state,
        today: today,
        projectId: _projectId,
      );
      _rows[state] = rows;
      _totals[state] = widget.store.stateCount(
        state,
        today: today,
        projectId: _projectId,
      );
      _more[state] = rows.length == Windows.list;
    }
    _drawnAt = widget.store.latestTaskChange(projectId: _projectId);
    _takenAt = DateTime.tryParse(
      widget.store.meta(MetaKey.fetchedAt) ?? '',
    )?.toLocal();
    _arrived = null;
  }

  /// Asks for the next window of one state, once the end of this one has been reached.
  ///
  /// The rows come from a file on the device, so there is nothing to wait for and no spinner to
  /// show. What it must not do is ask twice for the same window.
  void _widen(TaskState state) {
    if (_widening) return;
    _widening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _widening = false;
        return;
      }
      final held = _rows[state] ?? const <TaskLine>[];
      setState(() {
        final next = widget.store.inState(
          state,
          today: widget.clock(),
          projectId: _projectId,
          offset: held.length,
        );
        _rows[state] = [...held, ...next];
        _more[state] = next.length == Windows.list;
      });
      _widening = false;
    });
  }

  void _apply() => setState(_load);

  bool get _empty => _rows.values.every((rows) => rows.isEmpty);

  void _rowsArrived() {
    if (!mounted) return;
    // Nothing is being read yet, so there is no place to lose — and a list somebody watched fill
    // up is one they are already looking at. Either way the rows go straight in rather than
    // waiting behind a pill.
    if (_empty || (widget.arrivals?.watched ?? false)) {
      _apply();
      return;
    }
    final moved = widget.store.movedSince(_drawnAt, projectId: _projectId);
    if (moved.value == 0) return;
    setState(() => _arrived = moved);
  }

  Future<void> _pull() async {
    final take = widget.take;
    if (take != null) {
      setState(() => _taking = true);
      // A fetch that failed leaves the picture the device already had. Saying so is the band's
      // job, and it reads the same store — a list that stopped to report would be showing less
      // than it has.
      await take().catchError((Object _) {});
      if (!mounted) return;
      setState(() => _taking = false);
    }
    _showWhatArrived();
  }

  void _showWhatArrived() {
    _apply();
    // The one change that is not a surprise: the person asked for it.
    Touch.refreshApplied();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.clock();
    final words = Words.of(context);
    final standing = standingOf(
      anythingHere: !_empty,
      failure: widget.failure,
      paired: widget.paired,
    );
    return Scaffold(
      appBar: AppBar(
        title: _title(),
        actions: [
          // The way to the settings: three choices opened a handful of times a year, which is
          // not what a third of the bottom bar is for. The corner where a screen's way out to
          // what is behind it is looked for — and the same corner on all three tabs, so it is
          // not a thing to come back here for.
          if (widget.onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: words.settingsTitle,
              onPressed: widget.onOpenSettings,
            ),
        ],
        // A phone that holds nothing is not in one of four states — it is a phone with nothing on
        // it, and four empty switches would be four ways of finding that out.
        bottom: _empty
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final state in TaskState.values)
                    Tab(
                      text: NowScreen.tab(
                        words,
                        state,
                        _totals[state] ?? const Counted(0, false),
                      ),
                    ),
                ],
              ),
      ),
      body: Stack(
        children: [
          if (_empty)
            RefreshIndicator(onRefresh: _pull, child: _nothing(words, standing))
          else
            TabBarView(
              controller: _tabs,
              children: [
                for (final state in TaskState.values)
                  _state(state, words, today, standing),
              ],
            ),
          // While a fetch runs, a line and nothing else. A spinner over the list, or a skeleton in
          // place of it, would take away the old picture — which is the correct thing to be
          // reading until a newer one exists.
          if (_taking)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: Space.hair),
            ),
          // The one thing on this screen that appears without being asked for, so the one thing
          // that has to be seen arriving. It drops in from the top edge it is offering to take the
          // reader back to, and leaves the same way once it has been taken — which is what says
          // the rows went in, since the list underneath is never animated.
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: AnimatedSwitcher(
                duration: Motion.asked(context, Motion.notice),
                switchInCurve: Motion.curve,
                switchOutCurve: Motion.curve,
                transitionBuilder: (child, coming) => FadeTransition(
                  opacity: coming,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(coming),
                    child: child,
                  ),
                ),
                child: _arrived == null
                    ? const SizedBox.shrink()
                    : ActionChip(
                        avatar: const Icon(Icons.arrow_upward, size: Space.s5),
                        label: Text(NowScreen.arrived(words, _arrived!)),
                        onPressed: _showWhatArrived,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title() {
    final words = Words.of(context);
    // Nothing to choose between: one project is the title, and a menu offering the only answer
    // is a control that costs a tap and gives nothing back.
    if (_projects.length < 2) {
      return Text(
        _projects.isEmpty ? words.allProjects : _projects.single.name,
      );
    }
    final label = _projectId == null
        ? words.allProjects
        : _names[_projectId] ?? words.allProjects;
    return PopupMenuButton<ProjectChoice>(
      tooltip: words.chooseProject,
      initialValue: ProjectChoice(_projectId),
      onSelected: (chosen) => setState(() {
        _projectId = chosen.id;
        _load();
      }),
      itemBuilder: (context) => [
        PopupMenuItem(value: ProjectChoice.all, child: Text(words.allProjects)),
        for (final project in _projects)
          PopupMenuItem(
            value: ProjectChoice(project.id),
            child: Text(project.name),
          ),
      ],
      child: Semantics(
        label: '$label, ${words.chooseProject}',
        button: true,
        container: true,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  /// A device that has never had anything. There is no picture for a band to sit above, so the
  /// same words take the screen — which is also the only time this app shows an empty list, and it
  /// does not show one even then.
  Widget _nothing(Words words, Standing standing) => ListView(
    // Still a scroll, or there is nothing to pull on.
    physics: const AlwaysScrollableScrollPhysics(),
    children: [_takeLine(words), _band(standing, whole: true)],
  );

  Widget _band(Standing standing, {bool whole = false}) => StateBand(
    standing: standing,
    onPairAgain: widget.onPairAgain,
    whole: whole,
  );

  /// How old what is being read is, and the way to make it newer — the whole of the top.
  ///
  /// The two are one question asked in two halves — "how old is this" and "can I have a newer
  /// one" — so they are read together rather than the way out sitting off on its own.
  ///
  /// **The way out is a glyph, and the word is said rather than drawn.** The circling arrows are
  /// one of the few pictures whose meaning is settled, and beside the hour something was taken at
  /// nobody reads them as anything but "take it again". Two strings would spend the width of a
  /// one-line top on saying the same thing twice.
  ///
  /// The line is here whether or not a round has ever finished. The pull is the same fetch and
  /// costs nothing to keep, but it cannot be seen, and an operation that is only discovered by
  /// trying a gesture on it is one most people never have.
  Widget _takeLine(Words words) {
    final theme = Theme.of(context);
    final taken = _takenAt;
    return Padding(
      padding: const EdgeInsets.only(left: Space.gutter, right: Space.s2),
      child: Row(
        children: [
          if (taken != null)
            Expanded(
              child: TimeOnHold(
                when: taken,
                child: Text(
                  NowScreen.takenAt(
                    TimeFace.of(context),
                    taken,
                    now: widget.clock(),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          // Nothing to press on a phone with no route to take: the screen still draws what is on
          // the device, and a button that quietly did nothing would be worse than no button.
          if (widget.take != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: words.refresh,
              onPressed: _pull,
            ),
        ],
      ),
    );
  }

  /// One state, read to its end.
  ///
  /// What stands above the rows — how old the picture is, and how things stand — is the same on
  /// all four and scrolls away with them, because it is about the screen rather than about the
  /// state being read.
  Widget _state(
    TaskState state,
    Words words,
    DateTime today,
    Standing standing,
  ) {
    final rows = _rows[state] ?? const <TaskLine>[];
    final header = <Widget>[_takeLine(words), _band(standing)];
    final dates = state == TaskState.finished
        ? _dateHeadings(rows, now: today)
        : const <int, String>{};
    return RefreshIndicator(
      onRefresh: _pull,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            header.length +
            (rows.isEmpty ? 1 : rows.length) +
            ((_more[state] ?? false) ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          final place = index - header.length;
          if (rows.isEmpty) return _none(words);
          if (place < rows.length) {
            final line = rows[place];
            final row = TaskRow(
              line: line,
              today: today,
              // Movement is what this state is about, so freshness earns its width here and
              // nowhere else.
              movedAt: state == TaskState.inProgress
                  ? DateTime.tryParse(line.updatedAt)
                  : null,
              // Only where it tells the person something the title has not: narrowed to one, or
              // on a machine that holds only one, every row would carry the same name.
              projectName: _projectId == null && _projects.length > 1
                  ? _names[line.projectId]
                  : null,
              onOpen: () => widget.onOpen(line),
            );
            final date = dates[place];
            // The heading travels with the first row of its day rather than as an item of its
            // own, so a window arriving underneath cannot land between the two.
            return date == null
                ? row
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListHeading(title: date),
                      row,
                    ],
                  );
          }
          _widen(state);
          return const SizedBox(height: Stroke.rule);
        },
      ),
    );
  }

  /// Which rows of the finished state open a new day, and what that day is called.
  ///
  /// Finished work is all of it and it only grows, so the date is what says how far down someone
  /// has read — written in wherever it changes, and nowhere else. It is taken from the same
  /// instant the list is ordered by, or a row would sit under a day it did not end on.
  Map<int, String> _dateHeadings(List<TaskLine> rows, {required DateTime now}) {
    final face = TimeFace.of(context);
    final headings = <int, String>{};
    DateTime? standing;
    for (var place = 0; place < rows.length; place += 1) {
      final line = rows[place];
      final when = DateTime.tryParse(
        line.closedAt ?? line.updatedAt,
      )?.toLocal();
      if (when == null || DateUtils.isSameDay(standing, when)) continue;
      standing = when;
      headings[place] = dateHeading(face, when, now: now);
    }
    return headings;
  }

  /// A state with nothing in it.
  ///
  /// One quiet line rather than the empty face the app shows elsewhere: the switch above is still
  /// there with the other three states and their numbers on it, so the person is neither told
  /// nothing nor left without a way on. Nothing being blocked is good news, and good news does not
  /// need a screen of its own.
  Widget _none(Words words) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.pageGutter,
      vertical: Space.s7,
    ),
    child: Text(
      words.nothingInState,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
