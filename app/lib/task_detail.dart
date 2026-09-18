/// One task, read to the end.
///
/// This is where a list stops being a list. The order down the screen is the order somebody reads
/// it in when they are standing somewhere with a few minutes: what it is, whether it can move at
/// all, what it says, what it is tied to, and only then the conversation.
///
/// **Why it is stuck comes before what it says.** Reading a whole set of notes and finding out at
/// the bottom that the task is waiting on something else is the one order that wastes the minutes
/// the person actually had.
library;

// The store's `Chip` is a category value on a task, which is what this screen means by the word
// every time it uses it. Material's widget of the same name is not drawn here.
import 'package:flutter/material.dart' hide Chip;

import 'l10n/words.dart';
import 'store/backlog_queries.dart';
import 'store/backlog_store.dart';
import 'ui/detail.dart';
import 'ui/markdown.dart';
import 'ui/marks.dart';
import 'ui/refs.dart';
import 'ui/task_row.dart';
import 'ui/time.dart';
import 'ui/tokens.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.store,
    required this.taskId,
    required this.onOpenTask,
    required this.onOpenDecision,
    this.projectName,
    this.onProject,
    this.onValue,
    this.onLink,
    this.onShare = shareHandoff,
    this.clock = DateTime.now,
  });

  final BacklogStore store;
  final int taskId;

  final void Function(int taskId) onOpenTask;
  final void Function(int decisionId) onOpenDecision;

  /// Which project it belongs to. Shown whether or not a list was narrowed — the number names the
  /// task on its own, but where to go back to on the PC is written nowhere else.
  final String? projectName;
  final void Function(int projectId)? onProject;

  /// A category chip, pressed — the one list face, narrowed to that value.
  final void Function(int valueId)? onValue;

  /// A link in the body, pressed. Null leaves links as text; nothing is ever followed unasked.
  final void Function(String url)? onLink;

  /// Hands the three lines out to the OS. The app cannot write a word back to the backlog, so
  /// this and the number are the whole of what a thought had here can be carried away in.
  final Future<void> Function(String text) onShare;

  final DateTime Function() clock;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskLine? _task;
  String _notes = '';
  var _blockers = const <TaskLine>[];
  var _blocking = const <TaskLine>[];
  var _decisions = const <DecisionLine>[];
  var _chips = const <Chip>[];
  var _commits = const <String>[];
  var _attachments = const <AttachmentLine>[];
  var _comments = const <CommentLine>[];
  late Counted _commentCount;
  bool _commitsOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TaskDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.taskId != widget.taskId) setState(_load);
  }

  void _load() {
    final store = widget.store;
    final id = widget.taskId;
    _task = store.task(id);
    _notes = store.record('task', id)?['notes'] as String? ?? '';
    _blockers = store.blockers(id);
    _blocking = store.blocking(id);
    _decisions = store.decisionsFor(id);
    _chips = store.chips(id);
    _commits = store.commits(id);
    _attachments = store.attachments('task', id);
    _commentCount = store.commentCount(id);
    // A conversation is read forwards, so the window sits at the end of it. Past that the person
    // asks: a task somebody has left alone for a month is not a task whose whole timeline should
    // load itself.
    _comments = store.comments(id);
  }

  void _readEarlier() {
    final oldest = _comments.isEmpty ? null : _comments.first.id;
    final more = widget.store.comments(
      widget.taskId,
      limit: Windows.commentPage,
      before: oldest,
    );
    if (more.isEmpty) return;
    setState(() => _comments = [...more, ..._comments]);
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final today = widget.clock();
    final words = Words.of(context);
    return DetailFrame(
      ref: taskRef(widget.taskId),
      name: task?.title,
      missing: words.taskGone,
      // Only where there is something to send. A task the phone does not hold has a number and
      // nothing else, and a share sheet carrying one line is not the bridge this is for.
      onShare: task == null
          ? null
          : () => widget.onShare(
              handoffText(
                ref: taskRef(task.id),
                title: task.title,
                state: statusWords(words, task.status),
              ),
            ),
      head: task == null ? null : _head(context, words, task, today),
      children: task == null
          ? const []
          : [
              ..._stall(context, words, task, today),
              if (_notes.trim().isNotEmpty)
                MarkdownSections(source: _notes, onLink: widget.onLink),
              ..._chipsSection(context, words),
              ..._tiesSection(context, words),
              ..._attachmentsSection(context, words),
              ..._commitsSection(context, words),
              ..._commentsSection(context, words, today),
            ],
    );
  }

  Widget _head(
    BuildContext context,
    Words words,
    TaskLine task,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    return DetailHead(
      title: task.title,
      project: widget.projectName,
      onProject: widget.onProject == null
          ? null
          : () => widget.onProject!(task.projectId),
      marks: [
        StatusMark(task.status),
        if (task.priority != null) PriorityMark(task.priority),
        if (task.assigneeKind == 'ai')
          Text(words.markAi, style: theme.textTheme.labelMedium),
        TimeOnHold(
          when: DateTime.parse(task.updatedAt),
          child: Text(
            relativeTime(
              TimeFace.of(context),
              DateTime.parse(task.updatedAt),
              now: today,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (task.dueOn != null) DueMark(task.dueOn!, today: today),
        if (task.startOn != null)
          Text(
            words.stallStarts(
              dayLabel(TimeFace.of(context), task.startOn!, now: today),
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  List<Widget> _stall(
    BuildContext context,
    Words words,
    TaskLine task,
    DateTime today,
  ) {
    final reason = stallReason(TimeFace.of(context), task, today: today);
    if (reason == null) return const [];
    return [
      NoticePanel(
        icon: Icons.report_outlined,
        colour: Theme.of(context).colorScheme.error,
        text: reason,
        spoken: '${words.detailStalled}, $reason',
      ),
    ];
  }

  List<Widget> _tiesSection(BuildContext context, Words words) {
    if (_blockers.isEmpty && _blocking.isEmpty && _decisions.isEmpty) {
      return const [];
    }
    return [
      SectionHeading(words.ties),
      for (final one in _blockers)
        _tie(
          context,
          lead: words.waitingOn,
          ref: taskRef(one.id),
          title: one.title,
          // Whether the other one is finished is the whole of what waiting means.
          state: statusWords(words, one.status),
          onTap: () => widget.onOpenTask(one.id),
        ),
      for (final one in _blocking)
        _tie(
          context,
          lead: words.waitedOnBy,
          ref: taskRef(one.id),
          title: one.title,
          state: statusWords(words, one.status),
          onTap: () => widget.onOpenTask(one.id),
        ),
      for (final one in _decisions)
        _tie(
          context,
          lead: words.decisionsSection,
          ref: decisionRef(one.id),
          title: one.title,
          state: decisionStatusWords(words, one.state),
          onTap: () => widget.onOpenDecision(one.id),
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

  /// What the task is filed under, directly under what it says.
  ///
  /// It carries no heading of its own — it is one more thing the task *is*, not a section about
  /// it — so it stands with the body rather than among the sections that follow.
  List<Widget> _chipsSection(BuildContext context, Words words) {
    if (_chips.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: Space.s3),
        child: Wrap(
          spacing: Space.s3,
          runSpacing: Space.s1,
          children: [
            for (final chip in _chips)
              ActionChip(
                label: Text(words.chipLabel(chip.dimension, chip.value)),
                onPressed: widget.onValue == null
                    ? null
                    : () => widget.onValue!(chip.valueId),
              ),
          ],
        ),
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
        // Deliberately not a button. A row that looks pressable and does nothing is worse than a
        // row that never offered.
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

  List<Widget> _commitsSection(BuildContext context, Words words) {
    if (_commits.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      // A section heading that is also the way to open the section, so it keeps the heading's air
      // above and below rather than the even gap a row would take.
      InkWell(
        onTap: () => setState(() => _commitsOpen = !_commitsOpen),
        child: Padding(
          padding: const EdgeInsets.only(top: Space.s6, bottom: Space.s2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${words.commits} ${_commits.length}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Icon(_commitsOpen ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
      if (_commitsOpen)
        for (final sha in _commits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.hair),
            child: Text(
              // Nothing here can open one. The short form is what a person types on the PC.
              sha.substring(0, sha.length < 12 ? sha.length : 12),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: Lettering.mono,
              ),
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

/// A file's size, near enough. The row exists to say the file is there and roughly how big — a
/// figure to the byte would be precision about something nobody can open.
String fileSize(Words words, int bytes) {
  if (bytes < 1024) return words.fileSizeBytes(bytes);
  if (bytes < 1024 * 1024) {
    return words.fileSizeKilobytes((bytes / 1024).round());
  }
  return words.fileSizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
}
