/// One decision, as a list draws it.
///
/// It is built to sit in the same list as a task row, which is why it keeps the same two-line
/// shape: title, then the little that says whether it is worth opening. What differs is what goes
/// on the second line — a decision has no priority, no due day and nothing blocking it, and the
/// one thing it does have is whether the writing is finished.
library;

import 'package:flutter/material.dart';

import '../l10n/words.dart';
import '../store/backlog_queries.dart';
import 'marks.dart';
import 'refs.dart';
import 'theme.dart';
import 'time.dart';
import 'tokens.dart';

class DecisionRow extends StatelessWidget {
  const DecisionRow({
    super.key,
    required this.line,
    required this.today,
    required this.onOpen,
    this.projectName,
  });

  final DecisionLine line;

  /// The day the screen was drawn against, so a row and its neighbours agree on what "yesterday"
  /// was.
  final DateTime today;

  final VoidCallback onOpen;

  /// Null while the list is narrowed to one project.
  final String? projectName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = Words.of(context);
    final face = TimeFace.of(context);
    final aside = theme.textTheme.labelMedium?.copyWith(
      color: palette(context).textFaint,
      fontWeight: Lettering.normal,
    );
    final excerpt = line.matchLine?.trim();
    // When the writing was finished if it has been, when it was raised if it has not — either way,
    // the date the list is sorted by is the date the row shows.
    final when = DateTime.tryParse(line.decidedAt ?? line.createdAt);

    return SpokenAsOne(
      label: [
        decisionRef(line.id),
        line.title,
        ?projectName,
        decisionStatusWords(words, line.state),
        if (when != null) relativeTime(face, when, now: today),
        ?excerpt,
      ].join(', '),
      child: RowSurface(
        onOpen: onOpen,
        // Empty, and still there: a decision has neither of the two marks, and a list that mixes
        // the two kinds would step its titles in and out without it.
        lead: const RowLead(),
        title: line.title,
        second: [
          DecisionStatusMark(line.state),
          if (projectName != null)
            Text(
              projectName!,
              style: aside,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (when != null)
            Text(relativeTime(face, when, now: today), style: aside),
        ],
        excerpt: excerpt,
      ),
    );
  }
}
