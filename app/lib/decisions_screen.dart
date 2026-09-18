/// "Decisions" — all of them, newest first, and nothing in front of them.
///
/// A decision is not looked for, it is read: the person knows one was made and wants to see what
/// it said, and what they reach for it by is when it happened. That is a list in date order, and a
/// short one — a backlog holds thousands of tasks and tens of decisions — so the whole face is one
/// scroll with no question above it to answer first.
///
/// It sat behind the second tab of the search face until now, which put a search in front of the
/// one thing on this phone nobody searches for.
///
/// Two things it deliberately does not do.
///
/// * **Nothing is excluded by state.** One still being written is the one most worth reading,
///   and the row says which it is.
/// * **It is never ordered by anything but when.** The list is what memory reaches into, and
///   memory reaches by date.
///
/// The rows are read off the store when the face is arrived at rather than while it is being read
/// — the shell rebuilds it per visit — so nothing is swapped out from under a thumb halfway down.
library;

import 'package:flutter/material.dart';

import 'l10n/words.dart';
import 'store/backlog_queries.dart';
import 'store/backlog_store.dart';
import 'ui/decision_row.dart';
import 'ui/empty.dart';
import 'ui/measure.dart';
import 'ui/tokens.dart';
import 'ui/touch.dart';

class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({
    super.key,
    required this.store,
    required this.onOpen,
    this.take,
    this.clock = DateTime.now,
  });

  final BacklogStore store;

  /// Opening a row. Always pushed by the shell, whatever the width — a decision is opened from a
  /// detail as often as from a list.
  final void Function(DecisionLine line) onOpen;

  /// Goes and fetches, on whichever route this phone is on. Null where it has no route to take:
  /// the list is still drawn, off the copy the device already holds.
  final Future<void> Function()? take;

  /// Passed in rather than read here, so every row on the screen agrees about what today was.
  final DateTime Function() clock;

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  var _projects = const <({int id, String name})>[];
  var _names = const <int, String>{};
  var _decisions = const <DecisionLine>[];

  /// Whether the last window came back full. A full window is the only honest sign that asking
  /// again might bring more.
  var _more = false;
  var _widening = false;
  var _taking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Archived projects included: a project nobody adds to any more is exactly the one whose
    // decisions still explain the thing that outlived it.
    _projects = widget.store.projects(includeArchived: true);
    _names = {for (final project in _projects) project.id: project.name};
    _decisions = widget.store.decisions();
    _more = _decisions.length == Windows.list;
  }

  /// The thumb asking for a fresh picture. The only way rows change while the face is being read,
  /// which is what makes it not a surprise.
  Future<void> _pull() async {
    final take = widget.take;
    if (take != null) {
      setState(() => _taking = true);
      // A fetch that failed leaves the picture the device already had. The front screen's band is
      // what says so; a list that stopped to report would be showing less than it has.
      await take().catchError((Object _) {});
      if (!mounted) return;
      setState(() => _taking = false);
    }
    setState(_load);
    Touch.refreshApplied();
  }

  /// Asks for the next window once the end of this one has been reached.
  ///
  /// The rows come from a file on the device, so there is nothing to wait for and no spinner to
  /// show. What it must not do is ask twice for the same window.
  void _widen() {
    if (_widening) return;
    _widening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _widening = false;
        return;
      }
      setState(() {
        final next = widget.store.decisions(offset: _decisions.length);
        _decisions = [..._decisions, ...next];
        _more = next.length == Windows.list;
      });
      _widening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = Words.of(context);
    final today = widget.clock();
    return Scaffold(
      appBar: AppBar(
        title: Text(words.tabDecisions),
        // While a fetch runs, a line and nothing else — the old picture is the correct thing to
        // be reading until a newer one exists.
        bottom: _taking
            ? const PreferredSize(
                preferredSize: Size.fromHeight(Space.hair),
                child: LinearProgressIndicator(minHeight: Space.hair),
              )
            : null,
      ),
      // Rows, not prose: a row is read down its left edge, so this stops narrower than a page of
      // text does. It is the one list that is a tab on its own — the other two are drawn beside a
      // detail, which is what holds them in.
      body: Measured.rows(
        child: RefreshIndicator(
          onRefresh: _pull,
          child: _decisions.isEmpty ? _nothing(words) : _rows(today),
        ),
      ),
    );
  }

  /// A phone the PC has not sent any yet. Still a scroll, or there is nothing to pull on.
  Widget _nothing(Words words) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      EmptyFace(
        mark: Icons.inbox_outlined,
        said: words.nothingHereYet,
        detail: words.nothingHereYetDetail,
      ),
    ],
  );

  Widget _rows(DateTime today) => ListView.builder(
    itemCount: _decisions.length + (_more ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == _decisions.length) {
        _widen();
        return const SizedBox(height: Stroke.rule);
      }
      final line = _decisions[index];
      return DecisionRow(
        line: line,
        today: today,
        // The list is every project at once, so a row says which one it came out of — and with
        // one project there is nothing to tell apart.
        projectName: _projects.length > 1 ? _names[line.projectId] : null,
        onOpen: () => widget.onOpen(line),
      );
    },
  );
}
