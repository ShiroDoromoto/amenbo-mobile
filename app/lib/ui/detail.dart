/// The frame a record is read in — the bar over it, the head it opens with, and the notices the
/// app puts above the body.
///
/// A task and a decision are read the same way, so they are drawn by the same pieces: a second
/// arrangement for the second one would only be a second thing to learn, and the two would drift
/// apart at every later change.
///
/// Two rules live here rather than in either screen:
///
/// * **the bar keeps saying what is open.** A detail is scrolled, and once the head has gone past
///   the top there is nothing left on the screen saying which record this is.
/// * **a notice is outlined, never filled.** A filled block is what a quote and a code fence in
///   the body are drawn as, and a notice wearing that face reads as part of what somebody wrote.
library;

import 'package:flutter/material.dart';

import '../l10n/words.dart';
import 'measure.dart';
import 'refs.dart';
import 'theme.dart';
import 'tokens.dart';

/// One record, from its bar down to the last section.
class DetailFrame extends StatefulWidget {
  const DetailFrame({
    super.key,
    required this.ref,
    required this.head,
    required this.children,
    this.name,
    this.onShare,
    this.missing,
  });

  /// How Amenbo names the record. Always on the screen: it is what the person types on the PC.
  final String ref;

  /// The head the body opens with — [DetailHead], or nothing where the phone does not hold the
  /// record.
  final Widget? head;

  final List<Widget> children;

  /// What the record is called. Carried into the bar once the head has scrolled away; null where
  /// the phone does not hold it.
  final String? name;

  /// Hands the record out to the OS. Null where there is nothing to send.
  final VoidCallback? onShare;

  /// What to say instead of a body, where the phone does not hold the record.
  final String? missing;

  @override
  State<DetailFrame> createState() => _DetailFrameState();
}

class _DetailFrameState extends State<DetailFrame> {
  final _scroll = ScrollController();
  final _head = GlobalKey();

  /// The air over the head, which is scrolled through before the head itself is.
  static const _above = Space.s3;

  /// Whether the head has gone up past the top of what is being read.
  bool _folded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final folded = _headGone();
    if (folded != _folded) setState(() => _folded = folded);
  }

  /// How far it has to be scrolled is measured, not written down: how tall the head is depends on
  /// the text size the person set, on how long the title is, and on whether it names a project.
  ///
  /// The head's height is asked for rather than its position — where it is drawn is a frame behind
  /// the offset being read here, and a fold decided on last frame's geometry sticks.
  bool _headGone() {
    if (!_scroll.hasClients) return false;
    final head = _head.currentContext?.findRenderObject();
    // Scrolled far enough that the list stopped building it, which is further than gone.
    if (head is! RenderBox || !head.hasSize) return true;
    return _scroll.offset >= _above + head.size.height;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = Words.of(context);
    final name = widget.name;
    final head = widget.head;
    return Scaffold(
      appBar: AppBar(
        // The ref is the address; the name is what the person recognises. Both are worth the bar,
        // and only one of them is already on the screen while the head is showing.
        title: Row(
          children: [
            RefChip(widget.ref),
            if (_folded && name != null) ...[
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        titleSpacing: Space.gutter,
        actions: [
          if (widget.onShare case final share?)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: words.share,
              onPressed: share,
            ),
        ],
      ),
      // A record is a page of prose, so it stops where prose stops. Pushed on a tablet it would
      // otherwise take the whole glass, which is the one place a detail is drawn without the list
      // beside it holding it in.
      body: head == null
          ? Center(child: Text(widget.missing ?? ''))
          : Measured.prose(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  _above,
                  Space.gutter,
                  Space.s7,
                ),
                children: [
                  KeyedSubtree(key: _head, child: head),
                  ...widget.children,
                ],
              ),
            ),
    );
  }
}

/// What a record is called, and the little that ranks it.
///
/// The order down the head is the order it is read in, and the four parts are deliberately not
/// four voices of the same size: the title is what the person came for, the project and the marks
/// are what it is filed under and where it stands, and the number is on the bar above. A head
/// where every part is drawn at one weight is a head with no first line.
class DetailHead extends StatelessWidget {
  const DetailHead({
    super.key,
    required this.title,
    required this.marks,
    this.project,
    this.onProject,
  });

  final String title;

  /// State, priority, when it last moved — quiet, and under the title.
  final List<Widget> marks;

  /// Which project it belongs to. Where to go back to on the PC is written nowhere else.
  final String? project;

  final VoidCallback? onProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = this.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (project != null)
          InkWell(
            onTap: onProject,
            child: TapTarget(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (onProject != null)
                      Icon(
                        Icons.chevron_right,
                        size:
                            (theme.textTheme.labelMedium?.fontSize ??
                                Lettering.xs) *
                            1.2,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s3),
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        Wrap(
          spacing: Space.s4,
          runSpacing: Space.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: marks,
        ),
        const Divider(),
      ],
    );
  }
}

/// The app saying something about the record — that it cannot start, that it is still unfinished.
///
/// Outlined, and in the colour of what it is saying. The body's own quotes and code fences are
/// filled blocks, and a notice drawn as one of those is read as a line somebody wrote into the
/// record rather than as the app's own remark about it.
class NoticePanel extends StatelessWidget {
  const NoticePanel({
    super.key,
    required this.icon,
    required this.colour,
    required this.text,
    this.spoken,
  });

  final IconData icon;
  final Color colour;
  final String text;

  /// Read out in place of [text], where the line alone does not say what it is about.
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      margin: const EdgeInsets.only(bottom: Space.s5),
      decoration: BoxDecoration(
        border: Border.all(color: colour, width: Stroke.rule),
        borderRadius: Corner.smooth,
      ),
      child: Row(
        children: [
          Icon(icon, color: colour),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
              semanticsLabel: spoken,
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading over one section of a detail.
///
/// The air above it is what divides the screen into sections; the air under it is what ties the
/// heading to the rows it gathers. They are two different rungs of the ladder on purpose — equal
/// gaps either side leave a heading floating between the section it ends and the one it begins.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s6, bottom: Space.s2),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
