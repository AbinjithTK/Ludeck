// One game, as a card on the tree.
//
// Extracted from the roadmap view so the ARRIVAL ANIMATION survives a layout
// change. The animation is a property of a game appearing, not of the shape it
// appears on, so it lives with the node rather than with the map.
//
// What it knows: its game, whether it just arrived, and how tall its cover is.
// What it does NOT know: where it sits, what branch it belongs to, or how the
// tree is laid out. That keeps the layout free to change again.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../tokens.dart';

/// A game's cover as a tappable card, with its title beneath it.
///
/// The title is NOT optional and not decoration. Two games with no cover art
/// render as the same generic tile, so a cover-only node is unreadable exactly
/// where the catalogue is weakest -- which is why the reference apps' unlabelled
/// nodes were the wrong thing to copy here.
class GameNode extends StatefulWidget {
  const GameNode({
    super.key,
    required this.item,
    required this.cardWidth,
    required this.onTap,
    this.onLongPress,
    this.branchName,
    this.animateIn = false,
    this.showTitle = true,
    this.circular = false,
    this.coverCache,
    this.onCoverFound,
  });

  final TreeItem item;

  /// Cover width. Height follows from `Tokens.size.coverRatio`, so a card can
  /// never be set to a shape that crops the art.
  final double cardWidth;

  final VoidCallback onTap;

  /// Long-press handler, or NULL to leave long-press alone.
  ///
  /// Null is the important case. When this node is wrapped in a
  /// `LongPressDraggable`, an `InkWell` here that also claims long-press sits
  /// DEEPER in the tree and wins the gesture arena -- so the drag silently never
  /// starts. Passing null is what lets the drag recognizer have the gesture.
  final VoidCallback? onLongPress;

  /// Which branch this game hangs on, for the SPOKEN label only.
  ///
  /// This is the whole answer to "hide the branch name but keep it accessible":
  /// the name is never painted next to the node, and it is always announced. A
  /// screen reader hears "Hades, on Finished someday, finished"; a sighted user
  /// sees an unlabelled tree.
  final String? branchName;

  /// Play the arrival animation on first build.
  final bool animateIn;

  /// Whether to paint the title under the card.
  final bool showTitle;

  /// Circular mode for the roadmap: a SQUARE cover fitted into a circle, with a
  /// circle-native placeholder and no card chrome or harvest badge (the roadmap
  /// node draws its own lifecycle ring instead). A rectangular card clipped into
  /// a circle showed a clipped band; this renders for the circle from the start.
  final bool circular;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  State<GameNode> createState() => _GameNodeState();
}

class _GameNodeState extends State<GameNode>
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
      // Starts DONE so a node that is not arriving is at full size on its first
      // frame: forgetting to start the animation must leave the node visible,
      // never invisible.
      value: widget.animateIn ? 0.0 : 1.0,
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: Tokens.motion.easeOut);
    // From 0.6 rather than 0: growing from nothing reads as a pop-in, growing
    // from a smaller card reads as settling into place.
    _scale = Tween(begin: 0.6, end: 1.0).animate(curve);
    _fade = Tween(begin: 0.0, end: 1.0).animate(curve);

    if (widget.animateIn) {
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
    final cardHeight = widget.cardWidth * Tokens.size.coverRatio;
    final cover = game.coverUrl;

    // Reduced motion: the arrival controller's duration collapses to zero, so a
    // just-added node lands at full size instantly instead of scaling in. It
    // still RESOLVES (runs listeners, ends at 1.0) rather than being skipped, so
    // no node is left half-grown. Read here because initState has no context.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _controller.duration = Tokens.motion.maybe(Tokens.motion.grow, reduceMotion: reduce);

    // Fired from build, which CoverArtCache is built to tolerate: it remembers a
    // lookup per game id, so a node rebuilding on every scroll frame still
    // reaches the network at most once.
    final cache = widget.coverCache;
    if (cache != null && (cover == null || cover.isEmpty)) {
      cache.request(game.igdbId, game.title, (url) {
        widget.onCoverFound?.call(game.igdbId, url);
      });
    }

    // Everything the node conveys, as one sentence, INCLUDING the branch whose
    // name is deliberately not painted anywhere.
    final announced = <String>[
      game.title,
      if (widget.branchName case final String branch) 'on $branch',
      item.isSeed
          ? 'Bud, recommended by ${item.entry.recommendedBy ?? 'someone'}'
          : item.entry.progress.label,
      if (item.isHarvested && (item.entry.rating ?? 0) > 0)
        'rated ${item.entry.rating} out of 5',
    ].join(', ');

    final card = widget.circular
        ? ClipOval(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Tokens.cosmos.panelDeep),
              child: (cover != null && cover.isNotEmpty)
                  ? Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          _NodePlaceholder(title: game.title),
                    )
                  : _NodePlaceholder(title: game.title),
            ),
          )
        : DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Only a harvested game glows: rewarding what happened, never marking
        // what has not. docs/DECISIONS.md forbids the latter.
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
          decoration: BoxDecoration(
            color: Tokens.cosmos.panelDeep,
            border: Border.all(color: Tokens.cosmos.panelEdge),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null && cover.isNotEmpty)
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      _NodePlaceholder(title: game.title),
                )
              else
                _NodePlaceholder(title: game.title),

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

    // Circular mode: a SQUARE cover clipped to a circle, filling the ring.
    final cardHeightEffective = widget.circular ? widget.cardWidth : cardHeight;

    final node = Semantics(
      button: true,
      label: announced,
      excludeSemantics: true,
      onLongPressHint:
          widget.onLongPress == null ? null : 'Change status',
      child: Material(
        color: Tokens.palette.bg.withValues(alpha: 0),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          // The gesture covers card AND title: the title used to sit outside it,
          // which left a dead region directly under the thing naming the target.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: widget.cardWidth,
                  height: cardHeightEffective,
                  child: card),
              if (widget.showTitle) ...[
                SizedBox(height: Tokens.space.xxs),
                SizedBox(
                  width: widget.cardWidth,
                  child: Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: Tokens.type.caption,
                      color: Tokens.palette.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

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

/// What a node shows with no cover art.
///
/// It carries the game's INITIALS, not just a generic controller glyph. A row of
/// identical controller tiles reads as a loading failure; initials read as "no
/// art on file for this game", which is the truth.
class _NodePlaceholder extends StatelessWidget {
  const _NodePlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initials = title
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return DecoratedBox(
      decoration: BoxDecoration(color: Tokens.cosmos.panelDeep),
      child: SizedBox.expand(
        child: Center(
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              fontSize: Tokens.type.title,
              color: Tokens.palette.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
