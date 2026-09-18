/// The small marks a row wears — priority, state, lateness, who is on it.
///
/// **None of them says anything with colour alone.** The screen is read at night, at arm's
/// length, and by people who do not separate the colours the same way, so every mark carries a
/// word or a shape that survives the colour being lost. Colour is the fastest of the three and it
/// is used — it is just never the only one.
///
/// They are also silent to a screen reader. A row is read as one sentence built by [rowLabel];
/// left to themselves these would interrupt it with the names of glyphs.
library;

import 'package:flutter/material.dart';

import '../l10n/words.dart';
import 'theme.dart';
import 'time.dart';
import 'tokens.dart';

/// Amenbo's `high` / `medium` / `low`, or none at all.
class PriorityMark extends StatelessWidget {
  const PriorityMark(this.priority, {super.key});

  final String? priority;

  @override
  Widget build(BuildContext context) {
    if (priority == null) return const SizedBox.shrink();
    return _Mark(
      icon: priorityLook(context, priority!).$1,
      colour: priorityLook(context, priority!).$2,
      text: priorityWords(Words.of(context), priority!),
    );
  }
}

/// Shape carries the ranking on its own: full, half, hollow. Colour says the same thing again,
/// faster, for whoever can use it.
(IconData, Color) priorityLook(BuildContext context, String priority) {
  final colours = palette(context);
  return switch (priority) {
    'high' => (Icons.circle, colours.priorityHigh),
    'medium' => (Icons.contrast, colours.priorityMedium),
    _ => (Icons.circle_outlined, colours.priorityLow),
  };
}

/// The column every row in every list begins with, and the reason each of their titles begins at
/// the same place.
///
/// It is the width that matters. A mark that is only as wide as it needs to be moves the title
/// beside it, and a column of titles that each start somewhere slightly different is a column the
/// eye has to re-find on every line — which is the whole cost of a list read in seconds.
///
/// So the marks in it are shapes at a fixed size rather than glyphs with words: the ranking is in
/// full / half / hollow, the word is in the sentence a screen reader is given ([rowLabel]), and
/// nothing here is allowed to grow sideways.
class RowLead extends StatelessWidget {
  const RowLead({super.key, this.priority});

  final String? priority;

  /// One slot and the gap that separates the column from the title.
  static const width = Space.s5 + Space.s3;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      // Sits the mark on the first line of the title rather than on the top of its line box.
      padding: const EdgeInsets.only(top: Space.hair),
      child: SizedBox(
        width: width,
        child: priority == null
            ? null
            : Icon(
                priorityLook(context, priority!).$1,
                size: Space.s4,
                color: priorityLook(context, priority!).$2,
              ),
      ),
    ),
  );
}

String priorityWords(Words words, String priority) => switch (priority) {
  'high' => words.priorityHigh,
  'medium' => words.priorityMedium,
  'low' => words.priorityLow,
  _ => priority,
};

/// Amenbo's status, for the places that show it outright — a detail, or a search result whose
/// row is not being read under the state it is in.
class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colours = palette(context);
    final (icon, colour) = switch (status) {
      'in_progress' => (Icons.play_arrow, colours.statusInProgress),
      'done' => (Icons.check, colours.statusDone),
      'rejected' => (Icons.close, colours.statusTodo),
      'blocked' => (Icons.block, colours.statusBlocked),
      _ => (Icons.radio_button_unchecked, colours.statusTodo),
    };
    return _Mark(
      icon: icon,
      colour: colour,
      text: statusWords(Words.of(context), status),
    );
  }
}

String statusWords(Words words, String status) => switch (status) {
  'todo' => words.statusTodo,
  'in_progress' => words.statusInProgress,
  'done' => words.statusDone,
  'rejected' => words.statusRejected,
  'blocked' => words.statusBlocked,
  _ => status,
};

/// A decision's own three states, as `decisionState` reads them off the record.
///
/// `draft` is the one that carries weight: the writing is unfinished, so nothing linked to it can
/// be started until the person goes back to the PC and finishes it. So it is the only one drawn
/// in the accent colour, while the two that are settled stay quiet.
class DecisionStatusMark extends StatelessWidget {
  const DecisionStatusMark(this.state, {super.key});

  final String state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, colour) = switch (state) {
      'draft' => (Icons.edit_outlined, scheme.primary),
      'decided' => (Icons.check, scheme.onSurfaceVariant),
      'rejected' => (Icons.close, scheme.onSurfaceVariant),
      _ => (Icons.remove, scheme.onSurfaceVariant),
    };
    return _Mark(
      icon: icon,
      colour: colour,
      text: decisionStatusWords(Words.of(context), state),
    );
  }
}

String decisionStatusWords(Words words, String state) => switch (state) {
  'draft' => words.decisionDraft,
  'decided' => words.decisionDecided,
  'rejected' => words.decisionRejected,
  _ => state,
};

/// A due day, saying in words when it has passed.
///
/// Lateness is not a state of its own — it lifts a task to the top of the one it is already in —
/// so this is where a person finds out, and "Overdue" has to be written rather than implied by
/// the date turning red.
class DueMark extends StatelessWidget {
  const DueMark(this.dueOn, {super.key, required this.today});

  final String dueOn;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colours = palette(context);
    final label = dueLabel(TimeFace.of(context), dueOn, today: today);
    final late = isOverdue(dueOn, today: today);
    return _Mark(
      icon: late ? Icons.priority_high : Icons.event_outlined,
      colour: late ? colours.dueOverdue : colours.dueFuture,
      text: label,
    );
  }
}

/// What a row is waiting on, with a mark that says at a glance that it is waiting.
///
/// The four states do not divide by this — a task waiting on something is `todo` like any other —
/// so this is the whole of how the person tells them apart while reading down the list. The glyph
/// does the telling apart and the words say which one it is; neither is enough alone, and colour
/// is not used to carry it at all.
class StallMark extends StatelessWidget {
  const StallMark(this.reason, {super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colour = palette(context).statusBlocked;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colour);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: (style?.fontSize ?? Lettering.sm) * 1.1,
            color: colour,
          ),
          const SizedBox(width: Space.s1),
          // Flexible, and not a fixed width: the row is laid out in a Wrap, which hands its whole
          // width down, so a long reason ends in an ellipsis instead of over the edge.
          Flexible(
            child: Text(
              reason,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

bool isOverdue(String dueOn, {required DateTime today}) =>
    dueOn.compareTo(isoDay(today)) < 0;

String dueLabel(TimeFace face, String dueOn, {required DateTime today}) {
  final words = face.words;
  final day = isoDay(today);
  if (dueOn.compareTo(day) < 0) {
    return words.dueOverdue(dayLabel(face, dueOn, now: today));
  }
  if (dueOn == day) return words.dueToday;
  return words.dueOn(dayLabel(face, dueOn, now: today));
}

/// One line of text and its glyph.
class _Mark extends StatelessWidget {
  const _Mark({required this.icon, required this.colour, required this.text});

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colour);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The glyph follows the text size rather than sitting at a fixed one, or it shrinks
          // away as soon as someone turns their text up.
          Icon(
            icon,
            size: (style?.fontSize ?? Lettering.xs) * 1.1,
            color: colour,
          ),
          const SizedBox(width: Space.s1),
          // Flexible, for the same reason a stall reason is: these sit in a Wrap, which hands its
          // whole width down, so a mark wider than the line it is on would run off the edge
          // rather than being moved to the next one. Nothing is cut — the word wraps and the mark
          // gets taller, because a state read as "In Bearbeitun…" is a state nobody can read.
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// Everything a row says, as one sentence.
///
/// A screen reader that walks the marks one at a time reads out a list of glyph names between
/// every two useful words. Rows are given this instead, and their contents are hidden — see
/// [SpokenAsOne].
String rowLabel(
  Words words, {
  required String ref,
  required String title,
  required String status,
  String? priority,
  String? assigneeKind,
  int comments = 0,
  String? due,
  String? stallReason,
  String? project,
  String? when,
  String? excerpt,
}) => [
  ref,
  title,
  // Only where the row shows it — a list narrowed to one project would otherwise say the same
  // name on every line.
  ?project,
  statusWords(words, status),
  if (priority != null) words.rowPriority(priorityWords(words, priority)),
  ?due,
  ?stallReason,
  ?when,
  if (assigneeKind == 'ai') words.rowAssignedToAi,
  if (comments > 0) words.comments(comments),
  // Last, and read as part of the row: it is why the row is in a list of results, and it is the
  // longest thing on it.
  ?excerpt,
].join(', ');

/// Reads [label] in place of whatever [child] would have said.
class SpokenAsOne extends StatelessWidget {
  const SpokenAsOne({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    container: true,
    button: true,
    child: ExcludeSemantics(child: child),
  );
}

/// A day as Amenbo writes one, so a `due_on` or a `start_on` can be compared against today
/// without either side being parsed into an instant.
String isoDay(DateTime when) {
  final local = when.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
