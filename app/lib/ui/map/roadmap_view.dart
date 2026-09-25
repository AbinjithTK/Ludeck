// The collection as a road you travel up.
//
// A Duolingo-shaped path, with ONE deliberate departure from that shape, and it
// is not a stylistic one: Duolingo's path is built on LOCKED future levels, and
// `docs/DECISIONS.md` forbids marking what the user has not done ("gamification
// may only reward what already happened"). The Tolan reference has the same
// padlock on its "Next Reading" card.
//
// So every node here is a game ALREADY on the tree. The path shows progression
// through what exists; it never gates content, never greys a node out, and has no
// locked state to reach. What it does show is completion -- a harvested game
// glows, an unharvested one does not -- which is the permitted direction: the
// absence of a reward is not a penalty.
//
// The SOURCE OF TRUTH is unchanged. Segments come from `LudeckStore.branches` in
// the user's own order and nodes from `LudeckStore.placements`, which is the same
// data `CollectionView` groups by. This is a different rendering of the tree, not
// a second model of it.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';

/// How far a node sits from the centre line, as a fraction of the usable width.
///
/// Centre, right, centre, left -- a serpentine, which is what makes a vertical
/// list read as a road rather than as a column. Four entries rather than two so
/// the path passes through the middle between swings; alternating hard
/// left-right produces a zigzag with no straight stretch and reads as a chart.
const List<double> _serpentine = [0.0, 0.62, 0.0, -0.62];

double _offsetFactor(int index) => _serpentine[index % _serpentine.length];

/// The collection, rendered as a roadmap.
///
/// Honours the same callback contract as `CollectionView` and `TreeScene`
/// (`onSelect` on tap, `onHold` on long-press) so the screen swaps one for
/// another with no other change.
///
/// Stateful for ONE reason: to know which games are NEW. "Animate a game
/// appearing" means animating the games that were not here last time, and that
/// is only knowable by remembering the previous id set across builds. Nothing
/// else here holds state -- the tree is still the single source of truth, and
/// this set is derived from it, never authoritative over it.
class RoadmapView extends StatefulWidget {
  const RoadmapView({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onHold,
    required this.topInset,
    required this.bottomInset,
    this.branches = const [],
    this.placements = const {},
    this.coverCache,
    this.onCoverFound,
    this.animateArrivals = true,
  });

  final List<TreeItem> items;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;

  /// The user's branches, in their order. Empty is the normal starting state.
  final List<Branch> branches;

  /// Which game ids hang on which branch id.
  final Map<int, List<int>> placements;

  /// Looks up cover art for a node that has none.
  ///
  /// This matters MORE here than in the list it replaced: a list row still reads
  /// as a row without its thumbnail, but a node on the map is essentially just
  /// its cover, so an unfilled one is a placeholder tile on a road. Null default
  /// for the same reason as elsewhere -- a widget test must not reach the network.
  final CoverArtCache? coverCache;

  /// Called when [coverCache] resolves a cover for a game that had none.
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  /// Whether a newly-arrived game animates onto its node.
  ///
  /// True in the app. A test turns it OFF so a node is at its final size on the
  /// first pump and geometry assertions do not race a 260ms spring -- the
  /// animation itself is covered by its own test that leaves it on.
  final bool animateArrivals;

  final double topInset;
  final double bottomInset;

  @override
  State<RoadmapView> createState() => _RoadmapViewState();
}

class _RoadmapViewState extends State<RoadmapView> {
  /// The game ids present at the last build.
  ///
  /// Nullable and null ONLY before the first build. That distinction is
  /// load-bearing: on the very first build every game is technically "not seen
  /// before", but animating the entire existing collection on app open would be
  /// a fireworks show, not a game appearing. So the first build seeds this set
  /// and animates nothing; only games that arrive AFTER it are new.
  Set<int>? _seen;

  /// Ids to play the arrival animation for on this build. Recomputed each build
  /// and consumed by the nodes; an id is in here for exactly the one build after
  /// it first appears.
  Set<int> _arriving = const {};

  @override
  void initState() {
    super.initState();
    _seen = {for (final i in widget.items) i.game.igdbId};
  }

  @override
  void didUpdateWidget(RoadmapView old) {
    super.didUpdateWidget(old);
    final current = {for (final i in widget.items) i.game.igdbId};
    final seen = _seen ?? const <int>{};
    // New = present now, absent last build. Not "count went up": a game could be
    // added while another is shelved in the same reload, and the arrival is
    // still an arrival.
    _arriving = widget.animateArrivals
        ? current.difference(seen)
        : const <int>{};
    _seen = current;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final topInset = widget.topInset;
    final bottomInset = widget.bottomInset;

    if (items.isEmpty) return _Empty(topInset: topInset);

    final grouped = _group();

    // reverse: true, so the path STARTS at the bottom of the screen and climbs.
    // That is the whole reading of a roadmap -- you are at the bottom and the
    // road goes up -- and it also means the initial scroll position is the
    // beginning of the path rather than an arbitrary offset into it.
    //
    // Children are therefore listed in path order and appear bottom-first: the
    // first branch sits at the bottom, the staging tray ends up at the top.
    return ListView(
      key: const Key('roadmap-list'),
      reverse: true,
      // Padding is VISUAL even on a reversed list: `top` is the top of the
      // screen regardless of which end index 0 sits at. Swapping these to
      // "match" the reversal put the add-button gap at the top of the screen and
      // let the last node run underneath the button.
      padding: EdgeInsets.fromLTRB(
          Tokens.space.md, topInset, Tokens.space.md, bottomInset),
      children: [
        for (final segment in grouped.segments) ...[
          _Segment(
            segment: segment,
            arriving: _arriving,
            onSelect: widget.onSelect,
            onHold: widget.onHold,
            coverCache: widget.coverCache,
            onCoverFound: widget.onCoverFound,
          ),
        ],
        // Last in the list means FIRST on screen, because the list is reversed.
        // The tray belongs at the far end of the road: a freshly shared game
        // waits there to be filed, which is a real state rather than an error.
        if (grouped.unplaced.isNotEmpty)
          _StagingTray(
            items: grouped.unplaced,
            arriving: _arriving,
            onSelect: widget.onSelect,
            onHold: widget.onHold,
            coverCache: widget.coverCache,
            onCoverFound: widget.onCoverFound,
          ),
      ],
    );
  }

  /// Branch segments plus whatever is on no branch.
  ///
  /// With no branches at all this returns ONE unlabelled segment holding
  /// everything, rather than a heap of "unplaced". A new install has no branches,
  /// and a single continuous road is the honest reading of a collection nobody
  /// has organised yet -- the same call `CollectionView` makes when it falls back
  /// to status grouping instead of showing one unnamed group.
  ({List<_SegmentData> segments, List<TreeItem> unplaced}) _group() {
    final items = widget.items;
    final branches = widget.branches;
    final placements = widget.placements;

    if (branches.isEmpty) {
      return (
        segments: [_SegmentData(key: 'all', label: null, items: items)],
        unplaced: const [],
      );
    }

    final byId = {for (final i in items) i.game.igdbId: i};
    final placed = <int>{};
    final segments = <_SegmentData>[];

    for (final branch in branches) {
      final ids = placements[branch.id] ?? const <int>[];
      final segmentItems = <TreeItem>[];
      for (final id in ids) {
        final item = byId[id];
        // A placement can point at a game the collection does not carry -- a
        // shelved row, most likely. Skipping keeps a segment's count equal to
        // the nodes drawn on it.
        if (item == null) continue;
        segmentItems.add(item);
        placed.add(id);
      }
      // An empty branch still gets a segment. The user made it deliberately and
      // removing it from the map would look like it had been deleted.
      segments.add(_SegmentData(
          key: 'branch-${branch.id}', label: branch.name, items: segmentItems));
    }

    return (
      segments: segments,
      unplaced:
          items.where((i) => !placed.contains(i.game.igdbId)).toList(),
    );
  }
}

class _SegmentData {
  const _SegmentData({required this.key, required this.label, required this.items});

  final String key;

  /// Null for the no-branches-yet single road, which has nothing to be called.
  final String? label;

  final List<TreeItem> items;
}

/// One branch: a labelled stretch of road with its games on it.
///
/// A fixed-height Stack rather than a nested list, because the trail has to be
/// drawn as ONE path through every node on the stretch and a painter cannot see
/// into a virtualised list. The height is computed from the node count, so the
/// stack and the painter agree by construction instead of by coincidence.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.arriving,
    required this.onSelect,
    required this.onHold,
    this.coverCache,
    this.onCoverFound,
  });

  final _SegmentData segment;

  /// Game ids that should play their arrival animation this build.
  final Set<int> arriving;

  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Tokens.size.nodeCard;
    final cardHeight = cardWidth * Tokens.size.coverRatio;
    // A title under every node.
    //
    // Duolingo and the Tolan reference both use unlabelled nodes, and copying
    // that here was wrong for this content: two games with NO cover art render as
    // the same generic tile, so a cover-only map is unreadable exactly where the
    // catalogue is weakest. The caption is what makes a node identifiable rather
    // than decorative.
    const captionHeight = 26.0;
    final nodeHeight = cardHeight + captionHeight;
    final rowHeight = nodeHeight + Tokens.space.lg;

    return Column(
      children: [
        // The sign renders BELOW its own stretch of road.
        //
        // The outer list is reversed but this Column is not, so a child listed
        // second is simply lower on screen. Combined with the reversal that puts
        // the sign at the end of the stretch you climb -- you pass the games, then
        // read what the branch was called. Verified on the device rather than
        // reasoned about: an earlier version of this comment claimed the sign
        // appeared above, which was wrong in exactly the way a reversed axis
        // invites.
        SizedBox(
          height: segment.items.isEmpty
              ? rowHeight * 0.6
              : rowHeight * segment.items.length,
          child: segment.items.isEmpty
              ? const _EmptyBranch()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final usable = (constraints.maxWidth - cardWidth) / 2;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TrailPainter(
                              count: segment.items.length,
                              rowHeight: rowHeight,
                              nodeHeight: nodeHeight,
                              captionHeight: captionHeight,
                              cardHeight: cardHeight,
                              usable: usable,
                              centre: constraints.maxWidth / 2,
                              // The trail is dim where no game on this stretch
                              // is harvested yet. It marks where the road goes,
                              // never that the user is behind on it.
                              walked:
                                  segment.items.any((i) => i.isHarvested),
                            ),
                          ),
                        ),
                        for (var i = 0; i < segment.items.length; i++)
                          Positioned(
                            // Index 0 at the BOTTOM: the list is reversed, so
                            // within a segment the road must climb too, or the
                            // order would flip at every segment boundary.
                            bottom:
                                i * rowHeight + (rowHeight - nodeHeight) / 2,
                            left: constraints.maxWidth / 2 +
                                _offsetFactor(i) * usable -
                                cardWidth / 2,
                            width: cardWidth,
                            height: nodeHeight,
                            child: _GameNode(
                              item: segment.items[i],
                              cardHeight: cardHeight,
                              animateIn:
                                  arriving.contains(segment.items[i].game.igdbId),
                              onTap: () => onSelect(segment.items[i]),
                              onLongPress: () => onHold(segment.items[i]),
                              coverCache: coverCache,
                              onCoverFound: onCoverFound,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        if (segment.label != null)
          Padding(
            padding: EdgeInsets.only(top: Tokens.space.xs, bottom: Tokens.space.lg),
            child: _Waypoint(
                label: segment.label!, count: segment.items.length),
          ),
      ],
    );
  }
}

/// The line the road follows, through every node on one stretch.
class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.count,
    required this.rowHeight,
    required this.nodeHeight,
    required this.captionHeight,
    required this.cardHeight,
    required this.usable,
    required this.centre,
    required this.walked,
  });

  final int count;
  final double rowHeight;
  final double nodeHeight;
  final double captionHeight;
  final double cardHeight;
  final double usable;
  final double centre;
  final bool walked;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;

    final paint = Paint()
      ..color = walked ? Tokens.cosmos.trail : Tokens.cosmos.trailDim
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // The card's centre, NOT the node box's: the caption sits below the card, so
    // the box centre is lower than the thing the road should visibly connect.
    // Derived from the same numbers the Positioned uses, so the two cannot drift.
    Offset pointFor(int i) {
      final boxBottom = i * rowHeight + (rowHeight - nodeHeight) / 2;
      final cardCentreFromBottom = boxBottom + captionHeight + cardHeight / 2;
      return Offset(
        centre + _offsetFactor(i) * usable,
        size.height - cardCentreFromBottom,
      );
    }

    final path = Path()..moveTo(pointFor(0).dx, pointFor(0).dy);
    for (var i = 1; i < count; i++) {
      final from = pointFor(i - 1);
      final to = pointFor(i);
      // A cubic rather than a line: the swing between offsets is what makes the
      // road look travelled. Control points sit at the vertical midpoint so each
      // curve leaves and enters its node vertically, which is what stops the
      // joins from showing as corners.
      final midY = (from.dy + to.dy) / 2;
      path.cubicTo(from.dx, midY, to.dx, midY, to.dx, to.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.count != count ||
      old.rowHeight != rowHeight ||
      old.nodeHeight != nodeHeight ||
      old.captionHeight != captionHeight ||
      old.cardHeight != cardHeight ||
      old.usable != usable ||
      old.centre != centre ||
      old.walked != walked;
}

/// A game on the road: its cover as a card, with a glow when harvested.
///
/// Stateful only to own the arrival animation. A game that just appeared grows
/// and fades onto its node once, using `Tokens.motion.grow` -- the same duration
/// `DECISIONS.md` reserves for "a fruit growing onto a branch when a game is
/// captured", which is exactly this event in the tree metaphor. It plays once
/// and never again: a node that animated on every rebuild would pulse on every
/// scroll.
class _GameNode extends StatefulWidget {
  const _GameNode({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.cardHeight,
    this.animateIn = false,
    this.coverCache,
    this.onCoverFound,
  });

  final TreeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Play the arrival animation on first build. Set by the view for a game that
  /// was not present at the previous build.
  final bool animateIn;

  /// How tall the cover card is. The caption takes whatever vertical space is
  /// left over, so this number and the node's own height together decide the
  /// caption's box -- see the Expanded in build.
  final double cardHeight;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  State<_GameNode> createState() => _GameNodeState();
}

class _GameNodeState extends State<_GameNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Tokens.motion.grow,
      // Starts DONE, so a node that is not arriving is at full size on its first
      // frame -- the animation is opt-in, and forgetting to start it must leave
      // the node fully visible rather than invisible.
      value: widget.animateIn ? 0.0 : 1.0,
    );
    // easeOut, never a bounce: DECISIONS.md reserves overshoot for motion the
    // user's own gesture put momentum into, and a game appearing is not that.
    final curve = CurvedAnimation(parent: _controller, curve: Tokens.motion.easeOut);
    // From 0.6, not 0: a card that grows from nothing reads as a pop-in, while
    // one that grows from a smaller card reads as it settling into place.
    _scale = Tween(begin: 0.6, end: 1.0).animate(curve);
    _fade = Tween(begin: 0.0, end: 1.0).animate(curve);

    if (widget.animateIn) {
      // After the first frame, so the node is laid out before it starts moving.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final game = item.game;
    final radius = BorderRadius.circular(Tokens.radius.card);

    // Stage 1 found that a node with no glow and no image is an invisible dark
    // disc. A cover card mostly solves that by having a picture in it -- but a
    // game with NO cover would hit exactly that problem, so the placeholder
    // carries its own fill, border and icon rather than relying on the glow.
    final cover = game.coverUrl;

    // Fired from build, which CoverArtCache is built to tolerate: it remembers an
    // in-flight or finished lookup per game id, so a node rebuilding on every
    // scroll frame still reaches the network at most once.
    final cache = widget.coverCache;
    if (cache != null && (cover == null || cover.isEmpty)) {
      cache.request(game.igdbId, game.title, (url) {
        widget.onCoverFound?.call(game.igdbId, url);
      });
    }

    final announced = <String>[
      game.title,
      item.isSeed
          ? 'Seed from ${item.entry.recommendedBy ?? 'somewhere'}'
          : item.entry.progress.label,
      if (item.isHarvested && (item.entry.rating ?? 0) > 0)
        'rated ${item.entry.rating} out of 5',
    ].join(', ');

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Only a harvested game glows. Rewarding what happened, never marking
        // what has not -- see the file header.
        boxShadow: item.isHarvested
            ? [
                BoxShadow(
                  color: Tokens.palette.accent.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Tokens.cosmos.panelDeep),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null && cover.isNotEmpty)
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const _NodePlaceholder(),
                )
              else
                const _NodePlaceholder(),

              // A harvested game is marked on the card itself, by FORM as
              // well as colour, so completion survives colour-blindness --
              // the same rule the collection row and the Rive fruit follow.
              if (item.isHarvested)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(Tokens.space.xxs),
                    child: Icon(Icons.check_circle,
                        size: 16, color: Tokens.palette.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final node = Semantics(
      button: true,
      label: announced,
      // The caption repeats the title, so without this a screen reader reads the
      // name twice -- once from the label and once from the Text below the card.
      excludeSemantics: true,
      onLongPressHint: 'Change status',
      // The gesture wraps the WHOLE node, card and caption together. It used to
      // wrap only the card, which meant tapping a game's own title did nothing --
      // a dead region directly under the thing naming the target.
      child: Material(
        color: Tokens.palette.bg.withValues(alpha: 0),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          child: Column(
            children: [
              SizedBox(height: widget.cardHeight, child: card),
              // Expanded, so the caption gets EXACTLY the leftover space and an
              // overflow is not expressible. A fixed caption height plus a gap was
              // the first attempt and it overflowed by 15px under the test font --
              // this project has already learned once that a budgeted number cannot
              // clear text whose height depends on font and scale, so the layout is
              // structured to make the question moot instead.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: Tokens.type.caption,
                        color: Tokens.palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // A node not arriving has controller value 1, so the transition is inert and
    // costs nothing. AnimatedBuilder rebuilds only this subtree as the spring
    // runs, not the whole road.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: node,
    );
  }
}

/// What a node shows when the game has no cover art.
///
/// Its own fill and border, deliberately: this is the case Stage 1 caught, where
/// a node with nothing bright in it disappears against the sky.
class _NodePlaceholder extends StatelessWidget {
  const _NodePlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Tokens.cosmos.panelDeep,
          border: Border.all(color: Tokens.cosmos.panelEdge),
        ),
        child: Center(
          child: Icon(Icons.videogame_asset_outlined,
              size: 20, color: Tokens.palette.textDim),
        ),
      );
}

/// The sign naming a stretch of road.
class _Waypoint extends StatelessWidget {
  const _Waypoint({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: count == 1 ? '$label, 1 game' : '$label, $count games',
      excludeSemantics: true,
      child: SoftCard(
        deep: true,
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.space.sm, vertical: Tokens.space.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 14, color: Tokens.palette.textDim),
            SizedBox(width: Tokens.space.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.text,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(width: Tokens.space.xs),
            Text(
              '$count',
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A branch with nothing on it yet.
///
/// Says only that the stretch is empty. No prompt, no count of what is missing,
/// no call to fill it -- `DECISIONS.md` rules out empty-state guilt, and a branch
/// the user made and has not used is not a failure.
///
/// It takes no label: the waypoint sign directly below already names the branch,
/// and repeating it here would say the name twice on one stretch of road.
class _EmptyBranch extends StatelessWidget {
  const _EmptyBranch();

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          'No games on this branch yet',
          style: TextStyle(
            fontSize: Tokens.type.caption,
            color: Tokens.palette.textDim,
          ),
        ),
      );
}

/// Games on no branch, in a tray at the end of the road.
///
/// A tray rather than nodes on the path, because they are not ON the road yet --
/// putting them in the line would claim a position the user never gave them.
/// Horizontally scrolling, so an unfiled backlog of any size fits without
/// squeezing the cards.
class _StagingTray extends StatelessWidget {
  const _StagingTray({
    required this.items,
    required this.arriving,
    required this.onSelect,
    required this.onHold,
    this.coverCache,
    this.onCoverFound,
  });

  final List<TreeItem> items;
  final Set<int> arriving;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Tokens.size.nodeCard;
    final cardHeight = cardWidth * Tokens.size.coverRatio;
    // Matches the road's caption allowance, so a card is the same size in the
    // tray as it is once the user files it onto a branch.
    const captionHeight = 26.0;

    return Padding(
      padding: EdgeInsets.only(bottom: Tokens.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: Tokens.space.xs),
            child: Semantics(
              header: true,
              label: items.length == 1
                  ? 'Not on a branch, 1 game'
                  : 'Not on a branch, ${items.length} games',
              excludeSemantics: true,
              child: Text(
                'NOT ON A BRANCH  ${items.length}',
                style: TextStyle(
                  fontSize: Tokens.type.caption,
                  color: Tokens.palette.textDim,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SizedBox(
            height: cardHeight + captionHeight,
            child: ListView.separated(
              key: const Key('roadmap-staging'),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: Tokens.space.sm),
              itemBuilder: (context, i) => SizedBox(
                width: cardWidth,
                child: _GameNode(
                  item: items[i],
                  cardHeight: cardHeight,
                  animateIn: arriving.contains(items[i].game.igdbId),
                  onTap: () => onSelect(items[i]),
                  onLongPress: () => onHold(items[i]),
                  coverCache: coverCache,
                  onCoverFound: onCoverFound,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing on the tree at all.
///
/// States the fact and names the one action that starts a road. No guilt, no
/// count of what is missing.
class _Empty extends StatelessWidget {
  const _Empty({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.md, topInset + Tokens.space.xl, Tokens.space.md, 0),
        child: Column(
          children: [
            GlowOrb(diameter: Tokens.size.orb * 0.4, glow: 0.4),
            SizedBox(height: Tokens.space.md),
            Text(
              'The road starts with one game.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Tokens.type.title,
                color: Tokens.palette.text,
              ),
            ),
            SizedBox(height: Tokens.space.xs),
            Text(
              'Share a link to Ludeck, or add one by name.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Tokens.type.body,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      );
}
