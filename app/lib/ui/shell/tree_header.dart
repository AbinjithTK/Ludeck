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
  });

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
    if (total == 0) return 'Nothing growing yet.';
    final onTree = total - seeds;
    if (onTree <= 0) return 'All buds, for now.';
    if (onTree == 1) return 'One on the tree.';
    return '$onTree on the tree.';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ladder = levelFor(harvested);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Tokens.space.md,
          Tokens.space.sm,
          Tokens.space.md,
          Tokens.space.sm,
        ),
        child: Column(
          key: const Key('screen-header'),
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
                      Text(_headline, style: text.displaySmall),
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
                    diameter: Tokens.size.orb * 0.42,
                    glow: 0.7,
                    onTap: onProfileTap,
                    child: Text(
                      '${ladder.level}',
                      style: TextStyle(
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

            SizedBox(height: Tokens.space.xs),

            Semantics(
              label: ladder.neededForNext == 0
                  ? 'Level ${ladder.level}, the top of the ladder'
                  : 'Level ${ladder.level}, '
                      '${(ladder.progress * 100).round()} percent to level '
                      '${ladder.level + 1}',
              excludeSemantics: true,
              child: PillProgress(value: ladder.progress),
            ),

            SizedBox(height: Tokens.space.sm),

            // Horizontally scrolling, which is also what the Tolan reference
            // does -- its bottom row runs off the screen edge rather than
            // squeezing its cards. Protects the large-text-scale case too.
            // The chip row is the header's SECONDARY information, and it is the
            // first thing to go when type gets large.
            //
            // Without this the header grows with the text-size setting until the
            // content area has nothing left -- at 2x it reached one pixel and the
            // add menu overflowed. Dropping the chips is honest rather than
            // lossy: every count in them is already in the level line and in the
            // Semantics labels above, so a screen-reader user loses nothing and a
            // large-type user gets a header that still fits on the screen.
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
      ),
    );
  }
}
