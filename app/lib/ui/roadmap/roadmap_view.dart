// The game collection as an editable roadmap of connected nodes.
//
// This replaces the tree renderer entirely. A game is a NODE; consecutive games
// are joined by a rounded elbow connector on a winding vertical path, the shape
// the references (Noom, Mimo, Liven) all use. It scrolls; it does not orbit,
// zoom in 3D, or paint a trunk. All the colour comes from `Tokens.cosmos`,
// which already carries a `trail` / `trailDim` pair documented for exactly this.
//
// Drop-in for the old `ProceduralTreeView`: the prop shape is deliberately the
// same (items, branches, placements, onSelect, onHold, cover cache, insets, the
// burst signals) so `main.dart` and the profile portrait re-point with no other
// change. The layout math is the pure, unit-tested `roadmap_layout.dart`; this
// file is the widget shell around it.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../map/game_node.dart';
import '../tokens.dart';
import 'roadmap_layout.dart';

class RoadmapView extends StatefulWidget {
  const RoadmapView({
    super.key,
    required this.items,
    this.branches = const [],
    this.placements = const {},
    this.onSelect,
    this.onHold,
    this.coverCache,
    this.onCoverFound,
    this.topInset = 0,
    this.bottomInset = 0,
    this.animateArrivals = true,
    this.interactive = true,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;

  /// Null (or interactive=false) makes the roadmap a PICTURE, not a control:
  /// the profile portrait passes no handlers so it cannot be half-interactive.
  final ValueChanged<TreeItem>? onSelect;
  final ValueChanged<TreeItem>? onHold;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  final double topInset;
  final double bottomInset;

  final bool animateArrivals;

  /// False on the portrait: no scrolling, no taps, fitted into its box.
  final bool interactive;

  @override
  State<RoadmapView> createState() => _RoadmapViewState();
}

class _RoadmapViewState extends State<RoadmapView> {
  /// Games shown on the roadmap, in roadmap order.
  ///
  /// Shelved rows are dropped: the roadmap is the active journey. Order is the
  /// list order for now; Stage 4 adds a persisted, user-editable order.
  List<TreeItem> get _visible =>
      widget.items.where((i) => !i.entry.shelved).toList();

  @override
  Widget build(BuildContext context) {
    final games = _visible;

    if (games.isEmpty) {
      return _EmptyRoadmap(topInset: widget.topInset);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final layout = layoutRoadmap(
          count: games.length,
          width: width,
          topInset: widget.topInset,
          bottomInset: widget.bottomInset,
        );

        final board = SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: Stack(
            children: [
              // The connectors, behind the nodes.
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoadPainter(
                    links: layout.links,
                    colour: Tokens.cosmos.trail,
                  ),
                ),
              ),
              // The nodes.
              for (final node in layout.nodes)
                _positioned(node, games[node.index]),
            ],
          ),
        );

        if (!widget.interactive) {
          // Portrait: fit the whole board into the given box, no scroll.
          return FittedBox(fit: BoxFit.contain, child: board);
        }

        return SingleChildScrollView(
          child: board,
        );
      },
    );
  }

  Widget _positioned(RoadNode node, TreeItem item) {
    final w = Tokens.size.nodeCard;
    final h = w * Tokens.size.coverRatio;
    // Centre the card on the node centre; the title sits below within the row.
    return Positioned(
      left: node.centre.dx - w / 2,
      top: node.centre.dy - h / 2,
      width: w,
      child: GameNode(
        item: item,
        cardWidth: w,
        showTitle: true,
        animateIn: widget.animateArrivals,
        coverCache: widget.coverCache,
        onCoverFound: widget.onCoverFound,
        onTap: () => widget.onSelect?.call(item),
        onLongPress:
            widget.onHold == null ? null : () => widget.onHold!.call(item),
      ),
    );
  }
}

/// Strokes the rounded elbow connectors.
///
/// Each link is an axis-aligned polyline with a corner radius. A straight link
/// (two points) is one line; an elbow (four points) is drawn segment by segment
/// with a quarter-circle arc at each interior corner via `conicTo`, so the bend
/// is a true rounded corner rather than a chamfer.
class _RoadPainter extends CustomPainter {
  _RoadPainter({required this.links, required this.colour});

  final List<RoadLink> links;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final link in links) {
      canvas.drawPath(_pathFor(link), paint);
    }
  }

  Path _pathFor(RoadLink link) {
    final pts = link.points;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2 || link.radius <= 0) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }
    // Rounded corners at each interior point: stop short of the corner, arc
    // through it toward the next segment. arcToPoint with a quarter radius is
    // the clean rounded elbow.
    for (var i = 1; i < pts.length - 1; i++) {
      final prev = pts[i - 1];
      final corner = pts[i];
      final next = pts[i + 1];
      final r = link.radius;
      final beforeCorner = _towards(corner, prev, r);
      final afterCorner = _towards(corner, next, r);
      path.lineTo(beforeCorner.dx, beforeCorner.dy);
      path.arcToPoint(
        afterCorner,
        radius: Radius.circular(r),
        clockwise: _clockwise(prev, corner, next),
      );
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  /// A point [distance] from [origin] toward [target].
  Offset _towards(Offset origin, Offset target, double distance) {
    final d = target - origin;
    final len = d.distance;
    if (len < 1e-6) return origin;
    return origin + d * (distance / len);
  }

  /// Winding of the turn prev->corner->next, for the arc sweep direction.
  bool _clockwise(Offset prev, Offset corner, Offset next) {
    final cross = (corner.dx - prev.dx) * (next.dy - corner.dy) -
        (corner.dy - prev.dy) * (next.dx - corner.dx);
    return cross < 0;
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.links != links || old.colour != colour;
}

/// The empty state: no games yet. A single dimmed node marker on the spine, so
/// the screen reads as "your roadmap starts here" rather than as a blank.
class _EmptyRoadmap extends StatelessWidget {
  const _EmptyRoadmap({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topInset + Tokens.space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: Tokens.size.nodeCard,
            height: Tokens.size.nodeCard,
            decoration: BoxDecoration(
              color: Tokens.cosmos.panel,
              borderRadius: BorderRadius.circular(Tokens.radius.panel),
              border: Border.all(color: Tokens.cosmos.panelEdge),
            ),
            child: Icon(Icons.add, color: Tokens.palette.textDim),
          ),
          SizedBox(height: Tokens.space.md),
          Text(
            'Add your first game to start the roadmap',
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.palette.textDim),
          ),
        ],
      ),
    );
  }
}
