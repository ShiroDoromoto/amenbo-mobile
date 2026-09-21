/// One look, for both platforms, built once from the one sheet of numbers (`tokens.dart`).
///
/// Material 3 is used as-is on iOS as well as Android. The app is read in bursts of well under a
/// minute, so the thing worth spending on is that a row reads the same wherever it is met — not
/// that a switch matches the platform it is drawn on.
///
/// Four rules are kept here rather than in each screen, because a screen that forgets one of them
/// looks fine to whoever wrote it:
///
/// * **nothing states its size.** Sizes come from the text theme, which follows the setting the
///   person made in their OS. A number written into a widget stops following it.
/// * **nothing states its colour, spacing or corner either.** They come from [Palette], [Space]
///   and [Corner], so the whole app can be moved at once.
/// * **no state is carried by colour alone.** Priority and lateness both come with a word or a
///   shape beside them — see `marks.dart`.
/// * **nothing pressable is smaller than a finger.** Whatever answers a tap is wrapped in
///   [TapTarget], which is the only place [Layout.touch] is read.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The palette the surrounding theme is drawn from.
///
/// Most colours reach a widget through `Theme.of(context).colorScheme`; this is for the ones
/// Material has no role for — what a status, a priority or a due day is drawn in.
Palette palette(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<_PaletteOf>()?.palette ?? paletteFor(theme.brightness);
}

/// Carries [Palette] on the theme.
///
/// It does not blend from one brightness to the other: these are the colours a mark is recognised
/// by, and half of one is not a colour Amenbo has. The swap happens inside the fade the rest of
/// the theme is already doing.
@immutable
class _PaletteOf extends ThemeExtension<_PaletteOf> {
  const _PaletteOf(this.palette);

  final Palette palette;

  @override
  _PaletteOf copyWith({Palette? palette}) =>
      _PaletteOf(palette ?? this.palette);

  @override
  _PaletteOf lerp(_PaletteOf? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

ThemeData viewerTheme(Brightness brightness) {
  final colours = paletteFor(brightness);
  return ThemeData(
    colorScheme: _scheme(brightness),
    textTheme: _textTheme,
    scaffoldBackgroundColor: colours.bg,
    // Read at night as much as in daylight, and often one-handed on the move, so targets stay at
    // the platform's comfortable size rather than being tightened to fit more rows in.
    visualDensity: VisualDensity.standard,
    listTileTheme: const ListTileThemeData(
      // Rows carry two or three lines; a fixed height would either clip them or leave a gap once
      // the text size goes up.
      minVerticalPadding: Space.s4,
    ),
    // Every rule in the app is this one — a hairline in the quiet border colour, with a rung of
    // the ladder either side of it.
    dividerTheme: DividerThemeData(
      color: colours.border,
      thickness: Stroke.rule,
      space: Space.s6,
    ),
    extensions: [_PaletteOf(colours)],
  );
}

/// Amenbo's colours, on the Material roles that draw them.
///
/// The roles Amenbo has no colour for — an error wash, the fixed pairs — keep what Material
/// derives from the accent. They are the ones nothing on these screens asks for; giving them
/// invented values would put colours on the glass that Amenbo does not have.
ColorScheme _scheme(Brightness brightness) {
  final colours = paletteFor(brightness);
  final opposite = paletteFor(
    brightness == Brightness.dark ? Brightness.light : Brightness.dark,
  );
  return ColorScheme.fromSeed(
    seedColor: colours.accent,
    brightness: brightness,
  ).copyWith(
    // One accent, and no second one: secondary and tertiary are given the same colour rather than
    // a hue Amenbo never shows.
    primary: colours.accent,
    onPrimary: colours.onAccent,
    primaryContainer: colours.accentWeak,
    onPrimaryContainer: colours.accentText,
    secondary: colours.accent,
    onSecondary: colours.onAccent,
    secondaryContainer: colours.accentWeak,
    onSecondaryContainer: colours.accentText,
    tertiary: colours.accent,
    onTertiary: colours.onAccent,
    tertiaryContainer: colours.accentWeak,
    onTertiaryContainer: colours.accentText,
    surfaceTint: colours.accent,

    error: colours.danger,
    onError: colours.onDanger,

    surface: colours.bg,
    onSurface: colours.text,
    onSurfaceVariant: colours.textMuted,
    surfaceContainerLowest: colours.containerLowest,
    surfaceContainerLow: colours.containerLow,
    surfaceContainer: colours.container,
    surfaceContainerHigh: colours.containerHigh,
    surfaceContainerHighest: colours.containerHigh,
    outline: colours.borderStrong,
    outlineVariant: colours.border,

    // What a snack bar is drawn on: the other brightness of the same set, so the one thing that
    // deliberately stands against the page still belongs to it.
    inverseSurface: opposite.container,
    onInverseSurface: opposite.text,
    inversePrimary: opposite.accent,
  );
}

/// The text sizes, on the Material styles that draw them.
///
/// Only the styles the app actually uses are named; the rest keep Material's own, which nothing
/// draws.
const _textTheme = TextTheme(
  headlineSmall: TextStyle(
    fontSize: Lettering.xl,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  titleLarge: TextStyle(
    fontSize: Lettering.xl,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  titleMedium: TextStyle(
    fontSize: Lettering.lg,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  titleSmall: TextStyle(
    fontSize: Lettering.md,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  bodyLarge: TextStyle(
    fontSize: Lettering.body,
    fontWeight: Lettering.normal,
    height: Lettering.leading,
  ),
  bodyMedium: TextStyle(
    fontSize: Lettering.md,
    fontWeight: Lettering.normal,
    height: Lettering.leading,
  ),
  bodySmall: TextStyle(
    fontSize: Lettering.sm,
    fontWeight: Lettering.normal,
    height: Lettering.leading,
  ),
  labelLarge: TextStyle(
    fontSize: Lettering.md,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  labelMedium: TextStyle(
    fontSize: Lettering.xs,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
  labelSmall: TextStyle(
    fontSize: Lettering.xxs,
    fontWeight: Lettering.medium,
    height: Lettering.leadingTight,
  ),
);

/// What a finger presses, held to the size a finger is.
///
/// It grows the area that answers the press without growing what is drawn, because the two are
/// different measurements: a ref set at the size of a label reads correctly and is a quarter of a
/// fingertip tall. Put it *inside* whatever takes the tap — an `InkWell` sized to this is also an
/// `InkWell` whose ripple shows what was hit — and it takes no more room than its child wherever
/// the child is already big enough.
class TapTarget extends StatelessWidget {
  const TapTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(
      minWidth: Layout.touch,
      minHeight: Layout.touch,
    ),
    // Sized to the child rather than to everything on offer, or a target in a row would take the
    // whole line for itself.
    child: Center(widthFactor: 1, heightFactor: 1, child: child),
  );
}

/// A title as every list draws it: it wraps to a second line and stops there.
///
/// At the largest text size a phone offers, a backlog title runs well past one line. Two lines is
/// what a row can give it without the rows around it being pushed off the screen, so the title
/// takes two and the rest is cut — which is legible, where an overflowing row is not.
class RowTitle extends StatelessWidget {
  const RowTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

/// The shape every row in every list has: a fixed column of marks, a first line that opens with
/// the row's number and runs on into its title, the little under it, and a rule where the next
/// row begins.
///
/// The rule is the row's own rather than something the lists put between them. Rows are two and
/// three lines tall and of differing heights, and without a line drawn across them a long title
/// and the aside under the row above it read as one block.
///
/// What goes under the title is laid out with space and not with separators. Dots between the
/// parts made them one enumeration at one weight, which is exactly what stops an eye picking the
/// one part that matters — so the parts arrive already differing in size and in colour, and the
/// gap between them is the only punctuation. They wrap rather than overflow: at the largest text
/// a phone offers, three of them do not fit across a narrow screen, and a row that has run out of
/// width should get taller rather than lose what it was saying.
class RowSurface extends StatelessWidget {
  const RowSurface({
    super.key,
    required this.onOpen,
    required this.lead,
    required this.ref,
    required this.title,
    required this.second,
    this.excerpt,
  });

  final VoidCallback onOpen;

  /// The fixed-width column — `RowLead` in `marks.dart`.
  final Widget lead;

  /// The number this row is called by on the PC, namespaced the way `refs.dart` writes it.
  ///
  /// It runs in the same text as the title rather than in a column of its own, so a title that
  /// wraps comes back to the left edge every other title starts at. It is plain text: the row
  /// opens on a tap, and a second thing to tap inside it would have to be aimed at. The number
  /// that copies itself is `RefChip`, on the detail.
  final String ref;

  final String title;

  /// What sits under the title, strongest first.
  final List<Widget> second;

  /// Why this row is in a list of search results, and nothing else.
  final String? excerpt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = excerpt;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: Stroke.rule,
          ),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: TapTarget(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter,
              vertical: Space.s4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                lead,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RowTitle('$ref $title'),
                      if (second.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.hair),
                          child: Wrap(
                            spacing: Space.s4,
                            runSpacing: Space.hair,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: second,
                          ),
                        ),
                      if (found != null && found.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.hair),
                          child: Text(
                            found,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading over a stretch of a list, saying what the rows under it are.
///
/// It is drawn heavier than the titles beneath it. A heading that is smaller or lighter than the
/// rows it gathers stops being the thing that divides the screen, and the person scrolling past
/// reads one long list instead of two short ones.
///
/// It carries no count. Where there is a number to give — the four states — it is on the switch
/// that opens them, which is where the person is looking before they have chosen one.
class ListHeading extends StatelessWidget {
  const ListHeading({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      container: true,
      label: title,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.s6,
            Space.gutter,
            Space.s1,
          ),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: Lettering.bold,
            ),
          ),
        ),
      ),
    );
  }
}
