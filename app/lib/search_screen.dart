/// "Search" — one list face, and the only way back to what stopped moving.
///
/// Three of the four things a person opens this app for start with something the PC did, and the
/// front screen answers those. This one answers the fourth, which starts in their own head: "how
/// did that thing end up". What they are after is almost always finished, often months ago, and
/// therefore behind the one state on the front screen that does not reach that far back.
///
/// Three rules shape it.
///
/// * **Nothing is excluded by state.** Done, rejected, and decisions nobody accepted all show up.
///   Filtering them out would remove exactly what is being looked for.
/// * **Newest first, never by relevance.** A relevance order cannot explain why one row is above
///   another, and memory reaches for things by when they happened.
/// * **It is the only list face there is.** Search words, a category value, one project — three
///   inputs into one screen, so that arriving from somewhere narrower does not need a screen of
///   its own. Whatever narrowing the person arrived with is shown as a chip they can take off,
///   which turns any of those into plain search.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n/words.dart';
import 'store/backlog_queries.dart';
import 'store/backlog_store.dart';
import 'store/recents.dart';
import 'ui/decision_row.dart';
import 'ui/empty.dart';
import 'ui/project_choice.dart';
import 'ui/task_row.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    required this.onOpenTask,
    required this.onOpenDecision,
    this.onOpenSettings,
    this.narrowing = const TaskQuery(),
    this.clock = DateTime.now,
    this.settle = const Duration(milliseconds: 300),
  });

  final BacklogStore store;

  final void Function(TaskLine line) onOpenTask;
  final void Function(DecisionLine line) onOpenDecision;

  /// Opening the settings from this corner. Null where this face was pushed rather than being a
  /// tab — the way out of a pushed screen is the arrow it already carries.
  final VoidCallback? onOpenSettings;

  /// What the person arrived holding — a chip from a detail, the project the front screen was
  /// narrowed to. Empty when they came here to type.
  final TaskQuery narrowing;

  /// Passed in rather than read here, so every row on the screen agrees about what today was.
  final DateTime Function() clock;

  /// How long the typing has to stop before the query runs. A backlog is searched from a phone
  /// one-handed on the move; running on every keystroke spends the device's battery answering
  /// prefixes nobody meant to ask about.
  final Duration settle;

  static String tab(Words words, String name, Counted count) =>
      labelWithCount(words, name, count);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _field = TextEditingController();
  Timer? _settling;

  String _text = '';

  // The narrowings that can arrive with the person. Each one is held here rather than read from
  // the widget, because taking one off is the point of showing it.
  int? _valueId;
  int? _projectId;

  var _projects = const <({int id, String name})>[];
  var _names = const <int, String>{};

  var _tasks = const <TaskLine>[];
  var _decisions = const <DecisionLine>[];
  var _taskTotal = const Counted(0, false);
  var _decisionTotal = const Counted(0, false);

  /// Whether the last page came back full. A full page is the only honest sign that asking again
  /// might bring more — the totals stop counting at the cap and cannot be used for it.
  var _moreTasks = false;
  var _moreDecisions = false;
  var _widening = false;

  var _terms = const <String>[];
  var _seenTasks = const <TaskLine>[];
  var _seenDecisions = const <DecisionLine>[];

  @override
  void initState() {
    super.initState();
    _valueId = widget.narrowing.valueId;
    _projectId = widget.narrowing.projectId;
    _text = widget.narrowing.text ?? '';
    _field.text = _text;
    // Archived projects included: a project nobody adds to any more is dropped from the front
    // screen and kept here, because how something ended up is what it is remembered for.
    _projects = widget.store.projects(includeArchived: true);
    _names = {for (final project in _projects) project.id: project.name};
    _load();
  }

  @override
  void dispose() {
    _settling?.cancel();
    _field.dispose();
    _tabs.dispose();
    super.dispose();
  }

  TaskQuery get _query =>
      TaskQuery(text: _text, valueId: _valueId, projectId: _projectId);

  void _load() {
    final query = _query;
    _tasks = widget.store.tasks(query);
    _taskTotal = widget.store.taskCount(query);
    _moreTasks = _tasks.length == Windows.list;
    // The other input is a task's — a decision wears no category value. Words and project are
    // what both halves share.
    _decisions = widget.store.decisions(text: _text, projectId: _projectId);
    _decisionTotal = widget.store.decisionCount(
      text: _text,
      projectId: _projectId,
    );
    _moreDecisions = _decisions.length == Windows.list;
    _terms = widget.store.recentTerms();
    _seenTasks = const [];
    _seenDecisions = const [];
    for (final seen in widget.store.recentlyViewed()) {
      // Read back from the store rather than remembered whole, so a row the PC has since changed
      // is shown as it is now, and one it deleted quietly drops off.
      switch (seen.kind) {
        case Seen.task:
          final line = widget.store.task(seen.id);
          if (line != null) _seenTasks = [..._seenTasks, line];
        case Seen.decision:
          final line = widget.store.decision(seen.id);
          if (line != null) _seenDecisions = [..._seenDecisions, line];
      }
    }
  }

  void _apply() => setState(_load);

  void _typed(String text) {
    _settling?.cancel();
    setState(() => _text = text);
    _settling = Timer(widget.settle, _apply);
  }

  /// The hand stopped for good — the keyboard's own search key.
  void _submitted() {
    _settling?.cancel();
    widget.store.remember(term: _text);
    _apply();
  }

  void _clear() {
    _settling?.cancel();
    _field.clear();
    setState(() {
      _text = '';
      _load();
    });
  }

  /// Everything, from a screen that answered nothing.
  ///
  /// The words and every narrowing go together rather than one at a time: what the person is
  /// saying by pressing it is that they would rather start again than work out which of the three
  /// things they are holding is the one keeping the row out.
  void _everything() {
    _settling?.cancel();
    _field.clear();
    setState(() {
      _text = '';
      _valueId = null;
      _projectId = null;
      _load();
    });
  }

  void _openTask(TaskLine line) {
    // The word and the row are remembered together: this is the moment the word is known to have
    // been worth typing.
    widget.store.remember(term: _text, seen: Seen(Seen.task, line.id));
    widget.onOpenTask(line);
  }

  void _openDecision(DecisionLine line) {
    widget.store.remember(term: _text, seen: Seen(Seen.decision, line.id));
    widget.onOpenDecision(line);
  }

  /// Asks for the next window once the end of this one has been reached.
  ///
  /// The rows come from a file on the device, so there is no waiting to report — a spinner here
  /// would flash rather than inform. What it must not do is ask twice for the same page.
  void _widen({required bool tasks}) {
    if (_widening) return;
    _widening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _widening = false;
        return;
      }
      setState(() {
        if (tasks) {
          final next = widget.store.tasks(_query, offset: _tasks.length);
          _tasks = [..._tasks, ...next];
          _moreTasks = next.length == Windows.list;
        } else {
          final next = widget.store.decisions(
            text: _text,
            projectId: _projectId,
            offset: _decisions.length,
          );
          _decisions = [..._decisions, ...next];
          _moreDecisions = next.length == Windows.list;
        }
      });
      _widening = false;
    });
  }

  /// Every narrowing in force, in the form that lets it be taken off.
  List<({String label, VoidCallback off})> _narrowings(Words words) => [
    if (_valueId != null)
      (
        label: _valueLabel(words, _valueId!),
        off: () => setState(() {
          _valueId = null;
          _load();
        }),
      ),
    if (_projectId != null)
      (
        label: _names[_projectId] ?? words.allProjects,
        off: () => setState(() {
          _projectId = null;
          _load();
        }),
      ),
  ];

  String _valueLabel(Words words, int valueId) {
    final held = widget.store.dimensionValue(valueId);
    return held == null
        ? '$valueId'
        : words.valueChip(held.dimension, held.value);
  }

  /// Whether the screen is showing what it holds rather than an answer to something.
  bool get _asked => _text.trim().isNotEmpty || _valueId != null;

  @override
  Widget build(BuildContext context) {
    final today = widget.clock();
    final words = Words.of(context);
    final narrowings = _narrowings(words);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          textInputAction: TextInputAction.search,
          onChanged: _typed,
          onSubmitted: (_) => _submitted(),
          decoration: InputDecoration(
            hintText: words.searchHint,
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: words.searchClear,
                    onPressed: _clear,
                  ),
          ),
        ),
        actions: [
          // The same mouth as the front screen's title, and for the same reason: with one project
          // there is nothing to choose between.
          if (_projects.length > 1)
            PopupMenuButton<ProjectChoice>(
              icon: const Icon(Icons.folder_outlined),
              tooltip: words.chooseProject,
              initialValue: ProjectChoice(_projectId),
              onSelected: (chosen) => setState(() {
                _projectId = chosen.id;
                _load();
              }),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ProjectChoice.all,
                  child: Text(words.allProjects),
                ),
                for (final project in _projects)
                  PopupMenuItem(
                    value: ProjectChoice(project.id),
                    child: Text(project.name),
                  ),
              ],
            ),
          // After the folder, and in the corner every tab keeps it in: the settings are looked
          // for in one place, not in whichever place the tab happens to put them.
          if (widget.onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: words.settingsTitle,
              onPressed: widget.onOpenSettings,
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: SearchScreen.tab(words, words.tabTasks, _taskTotal)),
            Tab(
              text: SearchScreen.tab(words, words.tabDecisions, _decisionTotal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (narrowings.isNotEmpty) _rail(narrowings),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_taskList(words, today), _decisionList(words, today)],
            ),
          ),
        ],
      ),
    );
  }

  /// The narrowings, on one rail above the results.
  ///
  /// One rail rather than a control per kind: they combine, they all came from somewhere else,
  /// and every one of them comes off the same way.
  Widget _rail(
    List<({String label, VoidCallback off})> narrowings,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(
      horizontal: Space.s4,
      vertical: Space.s1,
    ),
    child: Row(
      children: [
        for (final narrowing in narrowings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s1),
            child: InputChip(
              label: Text(narrowing.label),
              // Named rather than left to the theme: the way off is the point of the chip
              // being here at all.
              deleteIcon: const Icon(Icons.cancel),
              onDeleted: narrowing.off,
            ),
          ),
      ],
    ),
  );

  Widget _taskList(Words words, DateTime today) {
    final header = <Widget>[
      if (!_asked) ..._recent(words, _seenTasks.map(_seenTaskRow).toList()),
      if (!_asked && _tasks.isNotEmpty && _headed)
        ListHeading(title: words.allTasksNewest),
    ];
    return _window(
      header: header,
      rows: _tasks.length,
      more: _moreTasks,
      onWiden: () => _widen(tasks: true),
      row: (index) => TaskRow(
        line: _tasks[index],
        today: today,
        showStatus: true,
        // Nothing above a result says when it last moved, the way a state on the front screen
        // does — and a memory reaches for things by when they happened.
        movedAt: DateTime.tryParse(
          _tasks[index].closedAt ?? _tasks[index].updatedAt,
        ),
        projectName: _projectId == null && _projects.length > 1
            ? _names[_tasks[index].projectId]
            : null,
        onOpen: () => _openTask(_tasks[index]),
      ),
    );
  }

  Widget _decisionList(Words words, DateTime today) {
    final header = <Widget>[
      if (!_asked)
        ..._recent(words, _seenDecisions.map(_seenDecisionRow).toList()),
      if (!_asked && _decisions.isNotEmpty && _headed)
        ListHeading(title: words.allDecisionsNewest),
    ];
    return _window(
      header: header,
      rows: _decisions.length,
      more: _moreDecisions,
      onWiden: () => _widen(tasks: false),
      row: (index) => _decisionRow(_decisions[index], today),
    );
  }

  /// Whether anything is standing above the list that it needs to be told apart from.
  bool get _headed =>
      _terms.isNotEmpty || _seenTasks.isNotEmpty || _seenDecisions.isNotEmpty;

  /// What the person was doing here last time, shown while they have asked for nothing.
  ///
  /// The same thing is looked up again and again — a word half-remembered on Monday is the word
  /// typed again on Wednesday — so the two shortcuts are the words and the rows themselves.
  List<Widget> _recent(Words words, List<Widget> seen) => [
    if (_terms.isNotEmpty) ...[
      ListHeading(title: words.recentTerms),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s1),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final term in _terms)
              ActionChip(
                label: Text(term),
                onPressed: () {
                  _settling?.cancel();
                  _field.text = term;
                  setState(() {
                    _text = term;
                    _load();
                  });
                },
              ),
          ],
        ),
      ),
    ],
    if (seen.isNotEmpty) ...[ListHeading(title: words.recentlyOpened), ...seen],
  ];

  Widget _seenTaskRow(TaskLine line) => TaskRow(
    line: line,
    today: widget.clock(),
    showStatus: true,
    projectName: _projectId == null && _projects.length > 1
        ? _names[line.projectId]
        : null,
    onOpen: () => _openTask(line),
  );

  Widget _seenDecisionRow(DecisionLine line) =>
      _decisionRow(line, widget.clock());

  Widget _decisionRow(DecisionLine line, DateTime today) => DecisionRow(
    line: line,
    today: today,
    projectName: _projectId == null && _projects.length > 1
        ? _names[line.projectId]
        : null,
    onOpen: () => _openDecision(line),
  );

  /// One window of rows, with whatever stands above it, and the end that asks for the next one.
  Widget _window({
    required List<Widget> header,
    required int rows,
    required bool more,
    required VoidCallback onWiden,
    required Widget Function(int index) row,
  }) {
    if (rows == 0 && header.isEmpty) {
      final words = Words.of(context);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Two different empty screens, because the person is in two different places. One asked
          // for something and can widen; the other has a phone the PC has not fed yet, and the
          // way on is on the other screen.
          if (_asked)
            EmptyFace(
              mark: Icons.search_off,
              said: words.nothingMatched,
              detail: words.nothingMatchedDetail,
              action: (label: words.showEverything, onTap: _everything),
            )
          else
            EmptyFace(
              mark: Icons.inbox_outlined,
              said: words.nothingHereYet,
              detail: words.nothingHereYetDetail,
            ),
        ],
      );
    }
    return ListView.builder(
      itemCount: header.length + rows + (more ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final place = index - header.length;
        if (place < rows) return row(place);
        onWiden();
        return const SizedBox(height: Stroke.rule);
      },
    );
  }
}
