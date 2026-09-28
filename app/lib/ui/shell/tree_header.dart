// The top of the tree screen: who you are, and what the tree says about you.
//
// Built from the primitives in `ui/gamified/primitives.dart` rather than from
// fresh widgets, so the header and everything else on the gamified surface cannot
// drift into two looks.
//
// Layout is text-LEFT with the orb on the right, not Tolan's centred planet. The
// reason is that this is a compact bar above a working canvas, not a full profile
// screen: a centred 148pt orb would take a third of a phone's height before the
// user sees a single game. The orb, the level, the progress and the counts are all
// present; they are arranged for a header rather than for a splash.
//
// Every number comes from the collection (see `domain/level.dart`). Nothing here
// is decorative arithmetic.

import 'package:flutter/material.dart';

import '../../domain/level.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';

class TreeHeader extends StatelessWidget {
  const TreeHeader({
    super.key,
    required this.total,
    required this.harvested,
    required this.seeds,
    required this.branches,
    required this.skipped,
    required this.onSkippedTap,
    required this.onBranchesTap,
    required this.onProfileTap,
    this.maxHeight,
  });

  /// The tallest this header may be. Null means unbounded.
  ///
  /// Supplied by the screen laying the header out, because that is the only widget
  /// that reliably knows the height available -- reading it from `MediaQuery` here
  /// gave zero in every test that injects a `MediaQueryData` without a size, and
  /// collapsed the header to nothing. Beyond the ceiling the content scrolls, so
  /// no line is ever unreachable.
  final double? maxHeight;

  /// Games on the tree.
  final int total;

  /// Finished games. The only input to the level.
  final int harvested;

  final int seeds;
  final int branches;

  /// Rows the last load could not read. Zero means nothing is shown.
  final int skipped;

  final VoidCallback onSkippedTap;
  final VoidCallback onBranchesTap;

  /// Opens the profile. The orb is the affordance.
  final VoidCallback onProfileTap;

  /// The headline. Counts what EXISTS, never what is outstanding -- a count that
  /// can only go up is the whole difference between this and a backlog.
  String get _headline {
    if (total == 0) return 'Nothing here yet.';
    final onTree = total - seeds;
    if (onTree <= 0) return 'All wishlist.';
    if (onTree == 1) return 'One game.';
    return '$onTree games.';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ladder = levelFor(harvested);

    // The header may never take more than the ceiling its parent gives it, and
    // scrolls inside that ceiling.
    //
    // Being an ordinary Column sibling above the content stops the header
    // COVERING the tree, which is what the previous fix was for. It does not stop
    // the header from being taller than the screen: the tree sits in an Expanded,
    // so a header that wants more than the full height simply gets it, Expanded
    // collapses to nothing, and the Column overflows.
    //
    // That was not hypothetical. At the 2x system text size the header measured
    // 791pt of a 915pt phone -- 86%, with about 125pt left for the tree -- and it
    // took only a few points more before `header.bottom` passed `tree.top` and the
    // layout genuinely overlapped. Dropping the chip row and capping the headline
    // both help and neither is a bound, because the level sentence can always wrap
    // one more time.
    //
    // The ceiling comes from the PARENT, not from `MediaQuery.sizeOf` here. A
    // first attempt read the height off MediaQuery and shipped a header of zero
    // height in every test that injects a `MediaQueryData` without a size -- which
    // is most of them, and the symptom was the tree rendering at y=0 with the
    // header collapsed on top of it. The only widget that reliably knows how tall
    // the screen is, is the one laying this out.
    //
    // Null means unbounded, which is correct for a test pumping the header alone.
    final bounded = maxHeight == null
        ? _content(context, text, ladder)
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight!),
            child: SingleChildScrollView(
              child: _content(context, text, ladder),
            ),
          );

    // The key is on the header's FOOTPRINT, not on the column inside the scroll
    // view. A layout test measuring the inner column read the column's full
    // height, which once the content scrolls is larger than the space the header
    // actually occupies -- so it reported a 6pt overlap with the tree that did not
    // exist on screen. What a caller wants to know is how much room the header
    // takes, which is this box.
    return SafeArea(
      key: const Key('screen-header'),
      bottom: false,
      child: bounded,
    );
  }

  Widget _content(
    BuildContext context,
    TextTheme text,
    ({int level, double progress, int harvestedIntoLevel, int neededForNext})
        ladder,
  ) {
    return Padding(
        // Tighter than it was. The header was MEASURED at 266pt of a 915pt phone
        // -- 29%, essentially the third the brief complained about -- on a screen
        // whose entire subject is the tree below it. test/nav_shell_test.dart
        // holds the budget so it cannot drift back up.
        padding: EdgeInsets.fromLTRB(
          Tokens.space.md,
          Tokens.space.xs,
          Tokens.space.md,
          Tokens.space.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The headline's scale is CAPPED at 1.5.
                      //
                      // Uncapped, at the 2x system setting, the header measured
                      // 85% of the screen and the tree had nothing left -- a
                      // header that large is not an accessible header, it is a
                      // screen with the content pushed off it. This one line is
                      // capped rather than the whole header because its content is
                      // the one thing here that is fully duplicated elsewhere: the
                      // same counts are in the level line below and in the spoken
                      // labels, so nobody loses information. Everything else in
                      // the header still scales without limit.
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.5,
                        child: Text(_headline, style: text.displaySmall),
                      ),
                      SizedBox(height: Tokens.space.xxs),
                      Text(
                        // What the level MEANS, in words, so the number is not a
                        // bare score. At the top of the ladder it says so rather
                        // than showing a next step that does not exist.
                        ladder.neededForNext == 0
                            ? 'Level ${ladder.level} \u00B7 every harvest counts'
                            : 'Level ${ladder.level} \u00B7 '
                                '${ladder.neededForNext} more '
                                '${ladder.neededForNext == 1 ? 'harvest' : 'harvests'} '
                                'to ${ladder.level + 1}',
                        style: text.labelSmall,
                      ),
                      SizedBox(height: Tokens.space.xxs),
                      Semantics(
                        label: ladder.neededForNext == 0
                            ? 'Level ${ladder.level}, the top of the ladder'
                            : 'Level ${ladder.level}, '
                                '${(ladder.progress * 100).round()} percent to '
                                'level ${ladder.level + 1}',
                        excludeSemantics: true,
                        child: PillProgress(value: ladder.progress),
                      ),
                      if (skipped > 0) ...[
                        SizedBox(height: Tokens.space.xs),
                        GestureDetector(
                          onTap: onSkippedTap,
                          child: Text(
                            skipped == 1
                                ? '1 game could not be read. Tap to find out more.'
                                : '$skipped games could not be read. Tap to '
                                    'find out more.',
                            style: text.labelSmall
                                ?.copyWith(color: Tokens.palette.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: Tokens.space.sm),

                // The orb, and the way into the profile.
                //
                // It was the largest element in the header carrying the least
                // explanation -- a glowing circle holding a bare number, with
                // "Level N" already written in words beside it. Making it the
                // profile entry point gives the biggest thing on the screen a job,
                // and the profile is where the tree portrait that belongs in an
                // avatar slot actually lives.
                Semantics(
                  label: 'Level ${ladder.level}. Open your profile',
                  button: true,
                  excludeSemantics: true,
                  child: GlowOrb(
                    diameter: Tokens.size.orb * 0.34,
                    glow: 0.7,
                    onTap: onProfileTap,
                    child: Text(
                      '${ladder.level}',
                      style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.title,
                        color: Tokens.palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                // Branches lives here rather than in the add menu: that menu is
                // "ways a game gets onto the tree", and organising it is not one.
                //
                // `semanticLabel` on the Icon, not the `tooltip` alone: a
                // tooltip did NOT reach the semantics tree here, so the only
                // route to the branches screen announced nothing while every
                // other header control announced itself. Verified by dumping
                // the real tree, not by reading this code -- see
                // test/accessibility_semantics_test.dart.
                IconButton(
                  tooltip: 'Branches',
                  icon: Icon(Icons.account_tree_outlined,
                      semanticLabel: 'Branches',
                      color: Tokens.palette.textDim),
                  onPressed: onBranchesTap,
                ),
              ],
            ),

            // The level bar used to be a full-width child HERE, with a spacer
            // above it. It now lives inside the text column in the row above,
            // directly under the level line it describes -- which is both a
            // shorter header and a better pairing, since a bar sitting a gap away
            // from the sentence explaining it reads as a separate thing.

            // ONE spacer, not two. There used to be a `space.sm` here and another
            // inside the branch below, so the gap above the chips was double every
            // other gap in the header for no reason.
            if (MediaQuery.textScalerOf(context).scale(Tokens.type.caption) <
                Tokens.type.caption * 1.4) ...[
              SizedBox(height: Tokens.space.sm),
              EdgeFade(
                child: SingleChildScrollView(
                  key: const Key('header-chips'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      StatChip(
                          icon: Icons.check_circle,
                          value: '$harvested',
                          label: 'harvested'),
                      SizedBox(width: Tokens.space.sm),
                      StatChip(
                          icon: Icons.circle_outlined,
                          value: '$seeds',
                          label: seeds == 1 ? 'bud' : 'buds'),
                      SizedBox(width: Tokens.space.sm),
                      StatChip(
                          icon: Icons.account_tree_outlined,
                          value: '$branches',
                          label: branches == 1 ? 'branch' : 'branches'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
    );
  }
}
