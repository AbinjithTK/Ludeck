// The profile: the tree IS the avatar.
//
// `docs/FEATURES.md` specifies this directly -- "For Ludeck the tree goes where
// the avatar is, which is the same artifact as the share card". So this screen
// does not invent a portrait, a monogram or a generated character. It renders the
// user's own tree at the top and reads the collection back underneath it.
//
// That also settles what the header's glowing orb should eventually hold. Today
// it holds a bare level number, which is the largest element on the tree screen
// carrying the least self-explanation; the tree portrait here is the artifact
// that belongs in an avatar slot.
//
// NOTHING on this screen is a network call. It is a pure read of the same store
// the tree screen reads, which is why it can ship before any backend exists.
//
// Two things are deliberately absent, both because `docs/DECISIONS.md` forbids
// them rather than because they were forgotten:
//
//   * No streak, no "days active", no comparison to last month. "Seasons, not
//     streaks" -- a streak punishes a missed day, and `domain/season.dart` is
//     explicit that a season carries no rate, no percentage and no comparison to
//     a prior period, because all three invite the reading that the number can
//     fail.
//   * No completion percentage of the collection. That would turn the tree into
//     a backlog gauge, which is the thing this app exists not to be.
//
// Every number here comes from `domain/level.dart` or `domain/season.dart`, both
// pure functions over the collection, both tested. No figure is computed inline.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../domain/branch_tree.dart';
import '../../domain/level.dart';
import '../../domain/season.dart';
import '../../state/ludeck_store.dart';
import '../gamified/primitives.dart';
import '../onboarding/onboarding_screen.dart';
import '../orchard/fruit_look.dart';
import '../orchard/orchard_portrait.dart';
import '../orchard/orchard_view.dart' show treesOf, gamesOnTree;
import '../orchard/tree_style.dart';
import '../publish/publish_screen.dart';
import '../tokens.dart';

/// The profile route. Reads the store, so it needs no arguments -- the same
/// pattern `BranchScreen` uses.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore>();
    final items = store.items ?? const <TreeItem>[];

    return ProfileBody(
      items: items,
      branches: store.branches.length,
      // The SAME tree the home screen draws, from the same engine and the same
      // renderer -- not a second portrait keyed on different data.
      //
      // It used to be `TreeScene`: five Rive artboards whose limbs were keyed on
      // the PLATFORMS a game was owned on, so the profile drew platform limbs
      // while home drew the user's own branches. Two trees from one collection,
      // and neither could be fixed without the other drifting. It also rendered
      // games as anonymous grey spheres while the tray below showed real cover
      // art, and it carried a drag-to-rotate gesture the user judged worse than
      // a still tree.
      //
      // The SAME orchard the home screen draws: the fullest trees, their
      // games as the same fruit, on the same meadow. It replaced a roadmap
      // (2026-09-27), which was a third picture of the collection.
      //
      // Passed in rather than constructed inside the body so the body stays
      // testable without a canvas.
      hero: OrchardPortrait(trees: _portraitTrees(store, items)),
    );
  }

  static List<PortraitTree> _portraitTrees(LudeckStore store, List<TreeItem> items) {
    final trees = treesOf(store.branches);
    final styles = resolveTreeStyles(
        trees.map((b) => b.id).toList(), store.treeStyles);
    final shape = BranchTree(store.branches, store.placements);
    final byId = {for (final i in items) i.game.igdbId: i};
    return [
      for (final t in trees)
        () {
          final games = gamesOnTree(t, shape, byId);
          return (
            name: t.name,
            games: [for (final g in games) g.game],
            looks: [for (final g in games) lookOf(g)],
            style: styles[t.id] ?? TreeStyle.defaultFor(trees.indexOf(t)),
          );
        }(),
    ];
  }
}

/// Everything on the profile except where its data comes from.
///
/// Presentational and fully injectable, so a widget test can assert the labels,
/// the counts and the semantics without a store, a database or a Rive artboard.
class ProfileBody extends StatelessWidget {
  const ProfileBody({
    super.key,
    required this.items,
    required this.branches,
    required this.hero,
  });

  /// The whole collection. Counting happens here, through the domain functions,
  /// rather than being passed in pre-counted -- a caller that can pass its own
  /// totals is a caller that can pass wrong ones.
  final List<TreeItem> items;

  final int branches;

  /// The tree portrait.
  final Widget hero;

  @override
  Widget build(BuildContext context) {
    final season = summarise(items);
    final ladder = levelFor(season.harvested);

    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      // Without this the starfield stops at the app bar and the transparent bar
      // just shows the scaffold's flat fill, which is a band across the top of a
      // screen whose whole point is depth.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Not `Colors.transparent`: checker rule 1 requires every colour value to
        // resolve through the token file, and `SoftCard` already established this
        // as the idiom for "no fill".
        backgroundColor: Tokens.palette.bg.withValues(alpha: 0),
        elevation: 0,
        foregroundColor: Tokens.palette.text,
        title: Text(
          'Your tree',
          style: TextStyle(
            fontSize: Tokens.type.body,
            fontWeight: FontWeight.w600,
            color: Tokens.palette.text,
          ),
        ),
      ),
      body: CosmosBackdrop(
        child: SafeArea(
          // The body runs behind the app bar, so the top inset is handled in the
          // list's own padding below rather than by SafeArea -- SafeArea would
          // clear the status bar but not the bar itself.
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Tokens.space.md,
              // Clears the app bar. Both terms are real measurements, not a
              // guessed inset: the status-bar height from the window and the
              // toolbar's own constant. A default AppBar does not grow with the
              // text-size setting, so this cannot drift the way a hand-picked
              // number would.
              MediaQuery.paddingOf(context).top + kToolbarHeight,
              Tokens.space.md,
              Tokens.space.xl,
            ),
            children: [
              _Portrait(hero: hero),
              SizedBox(height: Tokens.space.sm),
              _ShareEntry(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PublishScreen()),
                ),
              ),
              SizedBox(height: Tokens.space.xs),
              _HowItWorksEntry(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                ),
              ),
              SizedBox(height: Tokens.space.lg),
              _Ladder(ladder: ladder),
              SizedBox(height: Tokens.space.lg),
              _SeasonBlock(season: season, branches: branches),
            ],
          ),
        ),
      ),
    );
  }
}

/// The entry point into publish consent. docs/DECISIONS.md: sharing is never
/// gated, so this is a plain tappable card, reachable by every user, with no
/// entitlement check anywhere near it.
class _ShareEntry extends StatelessWidget {
  const _ShareEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.ios_share, size: 18, color: Tokens.palette.accent),
            SizedBox(width: Tokens.space.sm),
            Expanded(
              child: Text(
                'Share your tree',
                style: TextStyle(
                  fontSize: Tokens.type.body,
                  fontWeight: FontWeight.w600,
                  color: Tokens.palette.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Tokens.palette.textDim),
          ],
        ),
      );
}

/// Re-opens onboarding. "Re-openable from settings" -- FEATURES.md's own
/// requirement for a first-run explainer that must not be a one-time-only
/// thing.
class _HowItWorksEntry extends StatelessWidget {
  const _HowItWorksEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 18, color: Tokens.palette.accent),
            SizedBox(width: Tokens.space.sm),
            Expanded(
              child: Text(
                'How Ludeck works',
                style: TextStyle(
                  fontSize: Tokens.type.body,
                  fontWeight: FontWeight.w600,
                  color: Tokens.palette.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Tokens.palette.textDim),
          ],
        ),
      );
}

/// The tree, framed as a portrait.
///
/// A fixed aspect rather than a fixed height: the share card is a fixed ratio
/// artifact, and this is meant to be the same artifact, so the frame here should
/// not drift from it when the phone changes.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.hero});

  final Widget hero;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Semantics(
            // The tree itself carries no text, so without this a screen reader
            // reaches the largest thing on the screen and finds nothing. The
            // wording is distinct from the app bar's title on purpose: two nodes
            // announcing "Your tree" makes a test that checks for one of them
            // pass on the other.
            label: 'A portrait of your tree',
            image: true,
            child: hero,
          ),
        ),
      );
}

/// Level, what it means in words, and the bar.
///
/// The number is never shown bare. A level with no sentence beside it is a score
/// the user has to guess the rules of.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.ladder});

  final ({
    int level,
    double progress,
    int harvestedIntoLevel,
    int neededForNext
  }) ladder;

  String get _meaning {
    if (ladder.neededForNext == 0) return 'The top of the ladder';
    final n = ladder.neededForNext;
    final games = n == 1 ? 'harvest' : 'harvests';
    return '$n more $games to level ${ladder.level + 1}';
  }

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Level ${ladder.level}',
              style: TextStyle(
                fontSize: Tokens.type.title,
                fontWeight: FontWeight.w700,
                color: Tokens.palette.text,
                letterSpacing: Tokens.type.trackingTitle,
              ),
            ),
            SizedBox(height: Tokens.space.xxs),
            Text(
              _meaning,
              style: TextStyle(
                fontSize: Tokens.type.body,
                color: Tokens.palette.textDim,
              ),
            ),
            SizedBox(height: Tokens.space.sm),
            // The bar is decoration over the sentence above it, which already
            // says the same thing in words -- so it is excluded from semantics
            // rather than read out as a second, vaguer version of it.
            ExcludeSemantics(
              child: PillProgress(value: ladder.progress),
            ),
          ],
        ),
      );
}

/// The season: four counts, in the metaphor's own words.
///
/// The words come from `Progress.tree` and `Ownership.tree` rather than being
/// typed here, so a reworded metaphor cannot leave this screen behind. The
/// status vocabulary is frozen in `docs/DECISIONS.md` and a checker rule fails
/// the build on a banned synonym.
class _SeasonBlock extends StatelessWidget {
  const _SeasonBlock({required this.season, required this.branches});

  final Season season;
  final int branches;

  @override
  Widget build(BuildContext context) {
    /// "1 game you finished", "3 games you finished". A screen reader saying
    /// "1 games" is the kind of detail nobody sees in a screenshot review.
    String games(int n, String tail) =>
        '$n ${n == 1 ? 'game' : 'games'} $tail';

    final rows = <({String word, int count, String sentence})>[
      (
        word: Progress.finished.tree,
        count: season.harvested,
        sentence: games(season.harvested, 'you finished'),
      ),
      (
        word: Progress.abandoned.tree,
        count: season.pressed,
        sentence: games(season.pressed, 'you set aside'),
      ),
      (
        word: Progress.untouched.tree,
        count: season.stillGrowing,
        sentence: games(season.stillGrowing, 'still to play'),
      ),
      (
        word: Ownership.spotted.tree,
        count: season.seeds,
        sentence: games(season.seeds, 'someone recommended'),
      ),
    ];

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This season',
            style: TextStyle(
              fontSize: Tokens.type.title,
              fontWeight: FontWeight.w700,
              color: Tokens.palette.text,
              letterSpacing: Tokens.type.trackingTitle,
            ),
          ),
          SizedBox(height: Tokens.space.xxs),
          Text(
            // Says what the number IS, so nobody reads it as a target they are
            // behind on.
            'Where your collection stands right now.',
            style: TextStyle(
              fontSize: Tokens.type.body,
              color: Tokens.palette.textDim,
            ),
          ),
          SizedBox(height: Tokens.space.sm),
          for (final row in rows)
            _CountRow(
              word: row.word,
              count: row.count,
              sentence: row.sentence,
            ),
          Divider(color: Tokens.cosmos.panelEdge, height: Tokens.space.lg),
          _CountRow(
            word: branches == 1 ? 'Branch' : 'Branches',
            count: branches,
            sentence: '$branches '
                '${branches == 1 ? 'branch' : 'branches'} on your tree',
          ),
        ],
      ),
    );
  }
}

/// One line of the season block: a word and a number.
///
/// A row, not a chip. Four bordered pills in a grid is the shape the tree
/// header already uses for three counts, and repeating it here would read as a
/// row of buttons -- which is a live complaint about the header, since only one
/// of its three chips actually does anything.
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.word,
    required this.count,
    required this.sentence,
  });

  final String word;
  final int count;

  /// The whole announcement, already pluralised by the caller. The metaphor word
  /// alone ("Pressed 1") does not tell an unfamiliar listener anything, and
  /// assembling the sentence here produced "1 games".
  final String sentence;

  @override
  Widget build(BuildContext context) => Semantics(
        label: sentence,
        excludeSemantics: true,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  word,
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    color: Tokens.palette.text,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: Tokens.type.body,
                  fontWeight: FontWeight.w700,
                  color: Tokens.palette.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
}
