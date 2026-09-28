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
import '../../services/entitlement_service.dart';
import '../../state/ludeck_store.dart';
import '../paywall/paywall_screen.dart';
import '../gamified/primitives.dart';
import '../onboarding/onboarding_screen.dart';
import '../orchard/fruit_look.dart';
import '../orchard/orchard_portrait.dart';
import '../orchard/orchard_view.dart' show treesOf, gamesOnTree;
import '../orchard/tree_style.dart';
import '../publish/share_sheet.dart';
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
///
/// Laid out by priority (2026-09-28, replacing a column of five outlined
/// cards): the orchard, full bleed, with the title over its sky; the level in
/// words; the one action, Share, as the only filled control on the screen; the
/// season as five numbers on one line; "How Ludeck works" as a quiet link at
/// the foot. No card, frame or box anywhere: space and type do the grouping.
class ProfileBody extends StatelessWidget {
  const ProfileBody({
    super.key,
    required this.items,
    required this.branches,
    required this.hero,
    this.onShare,
  });

  /// The whole collection. Counting happens here, through the domain functions,
  /// rather than being passed in pre-counted -- a caller that can pass its own
  /// totals is a caller that can pass wrong ones.
  final List<TreeItem> items;

  final int branches;

  /// The tree portrait.
  final Widget hero;

  /// Opens the share sheet. Defaults to the store-backed one.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final season = summarise(items);
    final ladder = levelFor(season.harvested);
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Not `Colors.transparent`: checker rule 1 requires every colour value
        // to resolve through the token file.
        backgroundColor: Tokens.palette.bg.withValues(alpha: 0),
        elevation: 0,
        foregroundColor: Tokens.palette.text,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: Tokens.space.xl),
        children: [
          // The orchard, edge to edge, fading into the page so it has no
          // frame; the title sits in its sky.
          Stack(children: [
            _Portrait(hero: hero),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Tokens.palette.bg.withValues(alpha: 0),
                        Tokens.palette.bg,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: Tokens.space.lg,
              right: Tokens.space.lg,
              top: top + kToolbarHeight,
              child: Text(
                'Your orchard',
                style: TextStyle(
                  fontSize: Tokens.type.display,
                  fontWeight: FontWeight.w700,
                  color: Tokens.palette.text,
                  letterSpacing: Tokens.type.trackingDisplay,
                  height: Tokens.type.leadingDisplay,
                ),
              ),
            ),
          ]),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Tokens.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Ladder(ladder: ladder),
                SizedBox(height: Tokens.space.lg),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('profile-share'),
                    onPressed: onShare ?? () => showShareSheet(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.palette.text,
                      foregroundColor: Tokens.palette.bg,
                      shape: const StadiumBorder(),
                      textStyle: TextStyle(
                          fontSize: Tokens.type.body, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: const Text('Share your orchard'),
                  ),
                ),
                SizedBox(height: Tokens.space.xl),
                _SeasonBlock(season: season, branches: branches),
                SizedBox(height: Tokens.space.xl),
                const _ProRow(),
                SizedBox(height: Tokens.space.sm),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                    ),
                    style: TextButton.styleFrom(foregroundColor: Tokens.palette.textDim),
                    child: const Text('How Ludeck works'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where Pro lives: one quiet row under the season, above "How Ludeck works".
/// Always reachable (Shipaton requires the paywall be reachable from the
/// running app), never in the way of the orchard or sharing, which are free.
class _ProRow extends StatelessWidget {
  const _ProRow();

  @override
  Widget build(BuildContext context) {
    final EntitlementService service;
    try {
      service = Provider.of<EntitlementService>(context, listen: false);
    } on ProviderNotFoundException {
      return const SizedBox.shrink(); // a test mounting the body alone
    }
    return StreamBuilder<bool>(
      stream: service.changes,
      initialData: service.isPro,
      builder: (context, snap) {
        final pro = snap.data ?? false;
        return Semantics(
          button: !pro,
          child: ListTile(
            key: const Key('profile-pro'),
            contentPadding: EdgeInsets.symmetric(horizontal: Tokens.space.sm),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radius.card)),
            tileColor: Tokens.palette.surface,
            leading: Icon(pro ? Icons.verified_rounded : Icons.auto_awesome_rounded,
                color: Tokens.palette.accent),
            title: Text(pro ? 'Ludeck Pro is on' : 'Ludeck Pro',
                style: TextStyle(
                    fontSize: Tokens.type.body,
                    fontWeight: FontWeight.w600,
                    color: Tokens.palette.text)),
            subtitle: Text(
                pro ? 'Thank you for growing with us' : 'See more in your collection',
                style: TextStyle(
                    fontSize: Tokens.type.caption, color: Tokens.palette.textDim)),
            trailing: pro
                ? null
                : Icon(Icons.chevron_right_rounded, color: Tokens.palette.textDim),
            onTap: pro
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PaywallScreen(service: service))),
          ),
        );
      },
    );
  }
}

/// The orchard as a portrait. A fixed 4:5 like the share card, which is the
/// same picture, so the two never drift.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.hero});

  final Widget hero;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 4 / 5,
        child: Semantics(
          // The tree itself carries no text, so without this a screen reader
          // reaches the largest thing on the screen and finds nothing.
          label: 'A portrait of your tree',
          image: true,
          child: hero,
        ),
      );
}

/// Level, what it means in words, and a thin line for how far along.
///
/// The number is never shown bare. A level with no sentence beside it is a
/// score the user has to guess the rules of.
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
  Widget build(BuildContext context) => Column(
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
            style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.textDim),
          ),
          SizedBox(height: Tokens.space.sm),
          // Decoration over the sentence above, which says the same thing.
          ExcludeSemantics(child: PillProgress(value: ladder.progress)),
        ],
      );
}

/// The season: five numbers on one line, each over its word in the
/// metaphor's own vocabulary.
///
/// The words come from `Progress.tree` and `Ownership.tree` rather than being
/// typed here, so a reworded metaphor cannot leave this screen behind.
class _SeasonBlock extends StatelessWidget {
  const _SeasonBlock({required this.season, required this.branches});

  final Season season;
  final int branches;

  @override
  Widget build(BuildContext context) {
    /// "1 game you finished", "3 games you finished".
    String games(int n, String tail) =>
        '$n ${n == 1 ? 'game' : 'games'} $tail';

    final stats = <({String word, int count, String sentence})>[
      (
        word: Progress.finished.tree,
        count: season.harvested,
        sentence: games(season.harvested, 'you finished'),
      ),
      (
        word: Progress.untouched.tree,
        count: season.stillGrowing,
        sentence: games(season.stillGrowing, 'still to play'),
      ),
      (
        word: Progress.abandoned.tree,
        count: season.pressed,
        sentence: games(season.pressed, 'you set aside'),
      ),
      (
        word: Ownership.spotted.tree,
        count: season.seeds,
        sentence: games(season.seeds, 'someone recommended'),
      ),
      (
        word: branches == 1 ? 'Tree' : 'Trees',
        count: branches,
        sentence: '$branches ${branches == 1 ? 'tree' : 'trees'} in your orchard',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This season',
          style: TextStyle(
            fontSize: Tokens.type.body,
            fontWeight: FontWeight.w600,
            color: Tokens.palette.text,
          ),
        ),
        SizedBox(height: Tokens.space.xxs),
        Text(
          // Says what the number IS, so nobody reads it as a target.
          'Where your collection stands right now.',
          style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim),
        ),
        SizedBox(height: Tokens.space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in stats)
              Expanded(
                child: _Stat(word: s.word, count: s.count, sentence: s.sentence),
              ),
          ],
        ),
      ],
    );
  }
}

/// One number over its word. [sentence] is the whole announcement, already
/// pluralised: the metaphor word alone ("Pressed 1") tells an unfamiliar
/// listener nothing.
class _Stat extends StatelessWidget {
  const _Stat({required this.word, required this.count, required this.sentence});

  final String word;
  final int count;
  final String sentence;

  @override
  Widget build(BuildContext context) => Semantics(
        label: sentence,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: Tokens.type.title,
                fontWeight: FontWeight.w700,
                color: Tokens.palette.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim),
            ),
          ],
        ),
      );
}
