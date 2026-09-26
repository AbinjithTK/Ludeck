// One node on the roadmap: a game as a circular chip on the path.
//
// The references (Noom, Mimo, Liven) all draw a node as a ROUND badge sitting on
// the line, with its label to the side, and the ring around it carries the
// state. That is what this is: a circular cover clip, a lifecycle RING around
// it, a small state badge, and the title beside it on the side away from the
// centre line. The cover itself and its accessibility come from `GameNode`,
// which already handles art, the harvest glow and the spoken label.
//
// The ring is the one place lifecycle is shown, and it obeys DECISIONS.md: it
// rewards what happened (a finished game gets a full gold ring) and never marks
// what has not (an untouched game gets a plain thin ring, not a warning). There
// is no "locked" or "overdue" state, by design.

import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../map/game_node.dart';
import '../tokens.dart';

/// Which side the title sits, so it faces outward from the centre line.
enum NodeTitleSide { left, right }

class RoadmapNode extends StatelessWidget {
  const RoadmapNode({
    super.key,
    required this.item,
    required this.diameter,
    required this.titleSide,
    required this.onTap,
    this.onLongPress,
    this.animateIn = false,
    this.coverCache,
    this.onCoverFound,
    this.titleWidth = 120,
  });

  final TreeItem item;

  /// The ring's outer diameter. The cover clip sits inside the ring.
  final double diameter;

  /// Which side the title label sits on (the side away from centre).
  final NodeTitleSide titleSide;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool animateIn;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;
  final double titleWidth;

  /// The ring colour and width for this game's lifecycle state.
  ///
  /// Finished -> a full, thick gold ring (the reward). Playing/installed -> a
  /// medium accent-dim ring (in progress, not a verdict). Spotted (a bud) -> a
  /// thin dim ring (present, unjudged). Untouched/abandoned -> the plainest
  /// ring. Nothing here marks a game as behind or locked.
  ({Color colour, double width, bool glow}) get _ring {
    if (item.entry.progress == Progress.finished) {
      return (colour: Tokens.palette.accent, width: 3.5, glow: true);
    }
    if (item.entry.ownership == Ownership.spotted) {
      return (colour: Tokens.palette.textDim, width: 2, glow: false);
    }
    switch (item.entry.progress) {
      case Progress.playing:
      case Progress.installed:
        return (colour: Tokens.cosmos.glow, width: 3, glow: false);
      default:
        return (colour: Tokens.cosmos.panelEdge, width: 2, glow: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ring;
    // The cover clip fits inside the ring with a hairline gap so the ring reads
    // as a ring, not as a border on the art.
    final inner = diameter - ring.width * 2 - 4;

    final chip = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring.colour, width: ring.width),
        boxShadow: ring.glow
            ? [
                BoxShadow(
                  color: Tokens.palette.accent.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: SizedBox(
          width: inner,
          height: inner,
          // GameNode in circular mode carries the cover art (square, clipped to
          // a circle), the network fetch and the spoken label. The harvest badge
          // and card chrome are off; this node's ring shows lifecycle instead.
          child: GameNode(
            item: item,
            cardWidth: inner,
            showTitle: false,
            circular: true,
            animateIn: animateIn,
            coverCache: coverCache,
            onCoverFound: onCoverFound,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
      ),
    );

    final label = SizedBox(
      width: titleWidth,
      child: Column(
        crossAxisAlignment: titleSide == NodeTitleSide.right
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign:
                titleSide == NodeTitleSide.right ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: Tokens.type.caption,
              color: Tokens.palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: Tokens.space.xxs / 2),
          Text(
            _stateLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign:
                titleSide == NodeTitleSide.right ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: Tokens.type.caption - 1,
              color: Tokens.palette.textDim,
            ),
          ),
        ],
      ),
    );

    // Title on the outward side; a gap between it and the chip.
    final children = titleSide == NodeTitleSide.right
        ? [chip, SizedBox(width: Tokens.space.sm), label]
        : [label, SizedBox(width: Tokens.space.sm), chip];

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: titleSide == NodeTitleSide.right
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: children,
    );
  }

  /// The lifecycle word shown under the title. Uses the plain-language label,
  /// not the tree metaphor -- the tree is gone.
  String get _stateLabel {
    if (item.entry.ownership == Ownership.spotted) return 'Wishlist';
    if (item.entry.progress == Progress.finished) return 'Finished';
    return item.entry.progress.label;
  }
}
