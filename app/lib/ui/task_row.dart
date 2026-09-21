/// One task, as every list draws it.
///
/// Two lines. The first is what the task is; the second is the little that decides whether to open
/// it — where it lives, why it is not moving, when it is due, who has it. The notes are
/// deliberately absent: a title that does not say what the task is will not be rescued by the
/// first forty characters of its body, and every row that carries an excerpt is a row that fits
/// fewer tasks on the glass.
///
/// A row that came out of a search gets a third line, and only there: when the word was found in a
/// body or a comment rather than in the title, the stretch around it is the answer to "why is this
/// one in my results", which nothing else on the row can give.
library;

import 'package:flutter/material.dart';

import '../l10n/words.dart';
import '../store/backlog_queries.dart';
import 'marks.dart';
import 'refs.dart';
import 'theme.dart';
import 'time.dart';
import 'tokens.dart';

/// A count as a heading prints it.
String countLabel(Words words, Counted counted) =>
    counted.overflowed ? words.countOverflow(Counted.cap) : '${counted.value}';

/// A name with how many are under it — one tab of a switch, on either screen that has one.
String labelWithCount(Words words, String name, Counted count) =>
    '$name ${countLabel(words, count)}';

/// Why a task cannot be started, in the words the person needs in order to act.
///
/// A named blocker comes first because it is the only one that says what to go and do.
///
/// **Every premise that holds a task back has a line here.** No list divides by them any more, so
/// this is the only place the person finds out — a start day still ahead included, which is a
/// stall nobody has to do anything about and therefore the easiest one to leave out.
///
/// **Amenbo's own `blocked` is not one of them.** It is the state rather than a premise, and every
/// row already says the state: the switch it is read under, the mark beside it wherever a row
/// stands on its own, and the sentence it is read aloud as. A line here as well only said it
/// twice, and in English said the same word twice.
String? stallReason(TimeFace face, TaskLine line, {required DateTime today}) {
  final words = face.words;
  final blocker = line.blockedBy;
  if (blocker != null) return words.stallBlockedBy(taskRef(blocker));
  final undecided = line.undecided;
  if (undecided != null) return words.stallUndecided(decisionRef(undecided));
  if (line.draft) return words.stallDraft;
  final start = line.startOn;
  if (start != null && start.compareTo(isoDay(today)) > 0) {
    return words.stallStarts(dayLabel(face, start, now: today));
  }
  return null;
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.line,
    required this.today,
    required this.onOpen,
    this.projectName,
    this.movedAt,
    this.showStatus = false,
  });

  final TaskLine line;

  /// The day the whole screen was drawn against, so a row and the heading over it cannot disagree
  /// about whether something is late.
  final DateTime today;

  final VoidCallback onOpen;

  /// Null while the list is narrowed to one project — repeating the same name down every row
  /// only takes width away from the titles.
  final String? projectName;

  /// When it last moved, for the one state where movement is the subject. Elsewhere freshness is
  /// not what the person is judging, and a time on every row reads as noise.
  final DateTime? movedAt;

  /// Whether to say what state it is in. A row read under the switch is already under its own
  /// state; a search result stands on its own, and there the state is half of what the person
  /// came back to find out.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = Words.of(context);
    final face = TimeFace.of(context);
    // The second line has two voices. What decides whether to open the row leads, in its own
    // mark; everything after it is context, and is smaller and paler so the eye can pass over it.
    final aside = theme.textTheme.labelMedium?.copyWith(
      color: palette(context).textFaint,
      fontWeight: Lettering.normal,
    );
    final reason = stallReason(face, line, today: today);
    final moved = movedAt;

    final excerpt = line.matchLine?.trim();
    final ref = taskRef(line.id);

    final second = <Widget>[
      if (showStatus) StatusMark(line.status),
      // Why it cannot move, or when it is wanted — whichever there is. This is the row's second
      // strongest thing, so it leads, and nothing else on the line is drawn as loudly.
      if (reason != null)
        StallMark(reason)
      else if (line.dueOn != null)
        DueMark(line.dueOn!, today: today),
      if (projectName != null)
        // The first thing to be pushed off when the line will not fit: which project a task is in
        // is worth knowing, and never worth as much as why it is stuck or when it is due.
        Text(
          projectName!,
          style: aside,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (line.assigneeKind == 'ai') Text(words.markAi, style: aside),
      if (moved != null)
        Text(relativeTime(face, moved, now: today), style: aside),
      if (line.comments > 0) Text(words.comments(line.comments), style: aside),
    ];

    return SpokenAsOne(
      label: rowLabel(
        words,
        ref: ref,
        title: line.title,
        status: line.status,
        priority: line.priority,
        assigneeKind: line.assigneeKind,
        comments: line.comments,
        due: reason == null && line.dueOn != null
            ? dueLabel(face, line.dueOn!, today: today)
            : null,
        stallReason: reason,
        project: projectName,
        when: moved == null ? null : relativeTime(face, moved, now: today),
        excerpt: excerpt,
      ),
      child: RowSurface(
        onOpen: onOpen,
        lead: RowLead(priority: line.priority),
        ref: ref,
        title: line.title,
        second: second,
        excerpt: excerpt,
      ),
    );
  }
}
