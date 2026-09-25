import 'package:flutter/material.dart';

import '../tokens.dart';

/// Where the pill can take you.
///
/// An enum rather than a list of strings, so a destination cannot be added to the
/// bar without the switch that routes it failing to compile.
enum NavDestination {
  tree('Tree', Icons.park_outlined),
  library('Library', Icons.grid_view_outlined),
  friends('Friends', Icons.people_outline),
  you('You', Icons.person_outline);

  const NavDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The app's navigation: a translucent pill floating over the sky.
///
/// ### Why a pill and not a tab bar
///
/// `docs/DECISIONS.md` records the choice. A material bottom tab bar reserves a
/// permanent opaque band on the one screen whose entire purpose is to show the
/// tree, and Tolan-style corner-only chrome hid Friends so thoroughly that a new
/// person would not find it. The pill floats: it lets the sky through, so the
/// tree still owns the full height of the screen, while every destination stays
/// labelled and one tap away.
///
/// ### What it replaced
///
/// Before this the only ways off the home screen were the profile orb and a 17dp
/// glyph, and the entire social surface sat four taps deep behind "See what a
/// visitor sees" on the user's own share card -- which meant you could only ever
/// visit your OWN tree.
///
/// ### Labels are not optional
///
/// Every destination carries its word, not just its glyph. Two of these
/// (`Library`, `You`) have no icon a first-time user would read unambiguously,
/// and an icon-only bar is the specific failure the rejected option had. The
/// label is also what a screen reader announces, so removing it to save height
/// would take the destination away from anyone not looking at the screen.
class NavPill extends StatelessWidget {
  const NavPill({
    super.key,
    required this.current,
    required this.onSelect,
    this.toPlace = 0,
  });

  /// The destination the user is looking at. Rendered as selected, and its own
  /// button does nothing when tapped -- re-navigating to where you already are
  /// is a no-op that only costs a rebuild.
  final NavDestination current;

  final ValueChanged<NavDestination> onSelect;

  /// Games not filed onto a named branch yet. Shown as a count on `Library`.
  ///
  /// This is the whole of what survives of the old soil strip. Nothing waits
  /// off-tree any more, so this is not a queue of things to deal with: it is a
  /// note that some of what is already growing has not been arranged. At zero it
  /// renders NOTHING rather than a zero, because a badge reading 0 is a chore
  /// with no work in it.
  final int toPlace;

  /// The pill's height at the current text scale.
  ///
  /// The pill grows with the system text size instead of clipping its labels. At
  /// the 2x setting a fixed 56 overflowed by 12 points, and the two ways to hold a
  /// fixed height were both worse: clipping hides the word, and dropping the word
  /// leaves an icon-only bar, which is the specific failure the rejected navigation
  /// option had. Growth is capped at 1.6 so navigation cannot eat the screen
  /// either -- past that the labels stop growing and the icons carry the size.
  ///
  /// `ChromeMetrics` reserves space using THIS function rather than its own copy
  /// of the arithmetic. Two copies of a number that must agree is how the scrim
  /// stopped matching the control it covers once before.
  static double heightFor(BuildContext context) {
    final scale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    return Tokens.size.navPill * scale;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Tokens.space.md,
          0,
          Tokens.space.md,
          Tokens.space.sm,
        ),
        child: Container(
          height: heightFor(context),
          decoration: BoxDecoration(
            color: Tokens.cosmos.panelDeep,
            borderRadius: BorderRadius.circular(Tokens.radius.pill),
            border: Border.all(color: Tokens.cosmos.panelEdge),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radius.pill),
            // InkWell needs a Material ancestor and a Container is not one -- the
            // pill threw "No Material widget found" on every layout test until
            // this was added. `MaterialType.transparency` rather than a coloured
            // Material because the pill's own translucent fill is what lets the
            // sky through, and a second opaque surface here would undo that. The
            // clip is what keeps the ripple inside the pill's rounded edge.
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  for (final d in NavDestination.values)
                    Expanded(
                      child: _NavButton(
                        destination: d,
                        selected: d == current,
                        badge: d == NavDestination.library ? toPlace : 0,
                        onTap: d == current ? null : () => onSelect(d),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? Tokens.palette.accent : Tokens.palette.text;
    return Semantics(
      button: true,
      selected: selected,
      // The label carries the state, because `selected:` alone is not spoken as
      // anything on every screen reader, and "Library" with no indication you are
      // already on it is how a blind user ends up tapping it repeatedly.
      label: selected
          ? '${destination.label}, current'
          : badge > 0
              ? '${destination.label}, $badge to place'
              : destination.label,
      // Without this the icon's own name and the visible word merge into the
      // label above, so a screen reader says "Library" twice and the count
      // twice. The label here is the whole announcement.
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radius.pill),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Excluded from semantics: the label above already says
                // everything, and without this a screen reader reads the icon's
                // own name and then the count a second time.
                Icon(destination.icon, size: 20, color: colour),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Tokens.space.xxs,
                      ),
                      constraints: const BoxConstraints(minWidth: 14),
                      decoration: BoxDecoration(
                        color: Tokens.palette.accent,
                        borderRadius: BorderRadius.circular(Tokens.radius.pill),
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.3,
                          color: Tokens.palette.bg,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
