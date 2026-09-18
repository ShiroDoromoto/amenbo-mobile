/// One decision, and what stands on it.
///
/// The same skeleton as a task's detail — number, project, title, state, body, ties, comments —
/// because the two are read the same way and a second layout would only be a second thing to
/// learn. It is literally the same pieces: the frame and the head come from `ui/detail.dart`, and
/// what differs is what a decision has instead of a deadline — whether the writing is finished,
/// and what is not moving until it is.
///
/// **A half-written one is the whole point of this screen.** A decision the person has not
/// finished writing is work they owe their own backlog, and everything linked to it reads
/// `ready:no` until they do, so it says so at the top rather than leaving the state to a word
/// beside the title.
library;

import 'package:flutter/material.dart';

import 'l10n/words.dart';
import 'store/backlog_queries.dart';
import 'store/backlog_store.dart';
import 'task_detail.dart';
import 'ui/detail.dart';
import 'ui/markdown.dart';
import 'ui/marks.dart';
import 'ui/refs.dart';
import 'ui/task_row.dart';
import 'ui/time.dart';
import 'ui/tokens.dart';

class DecisionDetailScreen extends StatefulWidget {
  const DecisionDetailScreen({
    super.key,
    required this.store,
    required this.decisionId,
    required this.onOpenTask,
    required this.onOpenDecision,
    this.projectName,
    this.onProject,
    this.onLink,
    this.onShare = shareHandoff,
    this.clock = DateTime.now,
  });

  final BacklogStore store;
  final int decisionId;

  final void Function(int taskId) onOpenTask;

  /// The decision this one stands on, or replaces. Walking that chain backwards is how a rule
  /// that looks arbitrary turns out to have been argued somewhere.
  final void Function(int decisionId) onOpenDecision;

  final String? projectName;
  final void Function(int projectId)? onProject;
  final void Function(String url)? onLink;
  final Future<void> Function(String text) onShare;
  final DateTime Function() clock;

  @override
  State<DecisionDetailScreen> createState() => _DecisionDetailScreenState();
}

class _DecisionDetailScreenState extends State<DecisionDetailScreen> {
  DecisionLine? _decision;
  String _body = '';
  var _edges = const <DecisionEdgeLine>[];
  var _tasks = const <TaskLine>[];
  var _attachments = const <AttachmentLine>[];
  var _comments = const <CommentLine>[];
  late Counted _commentCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DecisionDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.decisionId != widget.decisionId) setState(_load);
  }

  void _load() {
    final store = widget.store;
    final id = widget.decisionId;
    _decision = store.decision(id);
    _body = store.record('decision', id)?['body'] as String? ?? '';
    _edges = store.edgesFor(id);
    _tasks = store.tasksFor(id);
    _attachments = store.attachments('decision', id);
    _commentCount = store.decisionCommentCount(id);
    // The newest few — the same window a task's timeline opens with, for the same reason: a
    // conversation is read forwards.
    _comments = store.decisionComments(id);
  }

  void _readEarlier() {
    final oldest = _comments.isEmpty ? null : _comments.first.id;
    final more = widget.store.decisionComments(
      widget.decisionId,
      limit: Windows.commentPage,
      before: oldest,
    );
    if (more.isEmpty) return;
    setState(() => _comments = [...more, ..._comments]);
  }

  /// What is actually stopped by it — a task that is already finished was not waiting.
  int get _heldTasks => _tasks
      .where((task) => task.status != 'done' && task.status != 'rejected')
      .length;

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final today = widget.clock();
    final words = Words.of(context);
    return DetailFrame(
      ref: decisionRef(widget.decisionId),
      name: decision?.title,
      missing: words.decisionGone,
      onShare: decision == null
          ? null
          : () => widget.onShare(
              handoffText(
                ref: decisionRef(decision.id),
                title: decision.title,
                state: decisionStatusWords(words, decision.state),
              ),
            ),
      head: decision == null ? null : _head(context, words, decision, today),
      children: decision == null
          ? const []
          : [
              ..._unfinished(context, words, decision),
              if (_body.trim().isNotEmpty)
                MarkdownSections(source: _body, onLink: widget.onLink),
              ..._tiesSection(context, words),
              ..._tasksSection(context, words, today),
              ..._attachmentsSection(context, words),
              ..._commentsSection(context, words, today),
            ],
    );
  }

  Widget _head(
    BuildContext context,
    Words words,
    DecisionLine decision,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    // Decided when the writing was finished, raised when it has not been — either way the date on
    // the screen is the date the person would remember it by.
    final when = DateTime.tryParse(decision.decidedAt ?? decision.createdAt);
    return DetailHead(
      title: decision.title,
      project: widget.projectName,
      onProject: widget.onProject == null
          ? null
          : () => widget.onProject!(decision.projectId),
      marks: [
        DecisionStatusMark(decision.state),
        if (when != null)
          TimeOnHold(
            when: when,
            child: Text(
              relativeTime(TimeFace.of(context), when, now: today),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// The line that says this one is still the person's to finish.
  ///
  /// It stands where a task's reason for being stuck stands, and for the same reason: finding out
  /// at the bottom of the body that nothing can move is finding out too late.
  List<Widget> _unfinished(
    BuildContext context,
    Words words,
    DecisionLine decision,
  ) {
    if (!decision.draft) return const [];
    final held = _heldTasks;
    final line = held == 0
        ? words.stallDraft
        : '${words.stallDraft} · ${words.decisionHeld(held)}';
    return [
      NoticePanel(
        icon: Icons.edit_outlined,
        colour: Theme.of(context).colorScheme.primary,
        text: line,
      ),
    ];
  }

  List<Widget> _tiesSection(BuildContext context, Words words) {
    if (_edges.isEmpty) return const [];
    return [
      SectionHeading(words.ties),
      for (final edge in _edges)
        _tie(
          context,
          lead: edgeWords(words, edge.kind),
          ref: decisionRef(edge.targetId),
          title: edge.title,
          state: decisionStatusWords(words, edge.state),
          onTap: () => widget.onOpenDecision(edge.targetId),
        ),
    ];
  }

  Widget _tie(
    BuildContext context, {
    required String lead,
    required String ref,
    required String title,
    required String state,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return SpokenAsOne(
      label: '$lead, $ref, $title, $state',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s3),
          child: Row(
            children: [
              SizedBox(
                width: Layout.leadColumn,
                child: Text(
                  lead,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$ref  $state', style: theme.textTheme.labelMedium),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// The work this decision produced. It is the way back out: a decision reached from a search is
  /// otherwise a dead end, however much it explains.
  List<Widget> _tasksSection(
    BuildContext context,
    Words words,
    DateTime today,
  ) {
    if (_tasks.isEmpty) return const [];
    return [
      SectionHeading(words.tasksSection),
      for (final task in _tasks)
        TaskRow(
          line: task,
          today: today,
          onOpen: () => widget.onOpenTask(task.id),
        ),
    ];
  }

  List<Widget> _attachmentsSection(BuildContext context, Words words) {
    if (_attachments.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      SectionHeading(words.attachments),
      Text(
        words.attachmentsStayOnThePc,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      for (final file in _attachments)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          child: Row(
            children: [
              Icon(
                Icons.attach_file,
                size:
                    (theme.textTheme.bodyMedium?.fontSize ?? Lettering.md) *
                    1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.s3),
              Expanded(child: Text(file.filename)),
              Text(
                fileSize(words, file.bytes),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _commentsSection(
    BuildContext context,
    Words words,
    DateTime today,
  ) {
    if (_commentCount.value == 0) return const [];
    final theme = Theme.of(context);
    return [
      SectionHeading(
        '${words.commentsSection} ${countLabel(words, _commentCount)}',
      ),
      if (_comments.length < _commentCount.value)
        TextButton(onPressed: _readEarlier, child: Text(words.readEarlier)),
      for (final one in _comments)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    one.authorKind == 'ai' ? words.markAi : words.markYou,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: Space.s3),
                  TimeOnHold(
                    when: DateTime.parse(one.createdAt),
                    child: Text(
                      relativeTime(
                        TimeFace.of(context),
                        DateTime.parse(one.createdAt),
                        now: today,
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              MarkdownBody(
                blocks: parseMarkdown(one.text),
                onLink: widget.onLink,
              ),
            ],
          ),
        ),
    ];
  }
}

/// Amenbo's own words for one decision standing on another.
///
/// The edge is drawn from this decision outwards, so every one of these reads as something this
/// decision did to an older one.
String edgeWords(Words words, String kind) => switch (kind) {
  'builds_on' => words.edgeBuildsOn,
  'supersedes' => words.edgeSupersedes,
  'amends' => words.edgeAmends,
  _ => kind,
};
