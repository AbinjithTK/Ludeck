// The game collection as an editable roadmap of connected nodes.
//
// This replaces the tree renderer entirely. A game is a NODE; consecutive games
// are joined by a rounded elbow connector on a winding vertical path, the shape
// the references (Noom, Mimo, Liven) all use. It scrolls; it does not orbit,
// zoom in 3D, or paint a trunk. All the colour comes from `Tokens.cosmos`,
// which already carries a `trail` / `trailDim` pair documented for exactly this.
//
// Drop-in for the old `ProceduralTreeView`: the prop shape is deliberately the
// same (items, branches, placements, onSelect, onHold, cover cache, insets) so
// `main.dart` and the profile portrait re-point with no other change. The
// layout math is the pure, unit-tested `roadmap_layout.dart`; this file is the
// widget shell around it.

import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../tokens.dart';
import 'roadmap_layout.dart';
import 'roadmap_node.dart';

/// The node ring's outer diameter on the roadmap.
const double _kNodeDiameter = 78;

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

  /// The index up to which the path is "walked" -- the furthest game the user
  /// has engaged with (finished, playing or installed). Connectors up to and
  /// including this index are the bright `trail`; those after are `trailDim`.
  /// This is a where-you-are marker on a map, which DECISIONS.md permits, not a
  /// lock or an overdue mark, which it forbids.
  int _walkedThrough(List<TreeItem> games) {
    var last = -1;
    for (var i = 0; i < games.length; i++) {
      final p = games[i].entry.progress;
      if (p == Progress.finished ||
          p == Progress.playing ||
          p == Progress.installed) {
        last = i;
      }
    }
    return last;
  }

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
          nodeRadius: _kNodeDiameter / 2,
        );
        final walked = _walkedThrough(games);

        final board = SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: Stack(
            children: [
              // The connectors, behind the nodes. Split into the walked part
              // (bright) and the rest (dim): link i joins node i to node i+1, so
              // it is "walked" when node i+1 is within the walked range.
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoadPainter(
                    links: layout.links,
                    walkedColour: Tokens.cosmos.trail,
                    aheadColour: Tokens.cosmos.trailDim,
                    walkedThroughLink: walked - 1,
                  ),
                ),
              ),
              for (final node in layout.nodes)
                _positioned(node, games[node.index], width),
            ],
          ),
        );

        if (!widget.interactive) {
          return FittedBox(fit: BoxFit.contain, child: board);
        }

        return SingleChildScrollView(child: board);
      },
    );
  }

  Widget _positioned(RoadNode node, TreeItem item, double width) {
    final d = _kNodeDiameter;
    // The node's Row is chip + title; the CHIP must sit centred on the path
    // point, with the title extending outward. Give the row the full half-width
    // on the title side and pin the chip to the path x by offsetting the row.
    final titleSide =
        node.side == RoadSide.left ? NodeTitleSide.left : NodeTitleSide.right;

    // The row is [chip | title] (right side) or [title | chip] (left side). To
    // land the CHIP centre on node.centre.dx, the row's left edge is the chip
    // centre minus half the chip, minus (for a left title) the title block.
    final titleWidth = width * 0.32;
    final rowLeft = titleSide == NodeTitleSide.right
        ? node.centre.dx - d / 2
        : node.centre.dx - d / 2 - titleWidth - Tokens.space.sm;

    return Positioned(
      left: rowLeft,
      top: node.centre.dy - d / 2,
      child: RoadmapNode(
        item: item,
        diameter: d,
        titleSide: titleSide,
        titleWidth: titleWidth,
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

/// Strokes the rounded elbow connectors, walked part bright and the rest dim.
///
/// Each link is an axis-aligned polyline with a corner radius. A straight link
/// (two points) is one line; an elbow (four points) is drawn segment by segment
/// with a quarter-circle arc at each interior corner, so the bend is a true
/// rounded corner rather than a chamfer.
class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.links,
    required this.walkedColour,
    required this.aheadColour,
    required this.walkedThroughLink,
  });

  final List<RoadLink> links;
  final Color walkedColour;
  final Color aheadColour;

  /// Highest link index that is "walked" (bright). -1 means none are.
  final int walkedThroughLink;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < links.length; i++) {
      final paint = Paint()
        ..color = i <= walkedThroughLink ? walkedColour : aheadColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_pathFor(links[i]), paint);
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

  Offset _towards(Offset origin, Offset target, double distance) {
    final d = target - origin;
    final len = d.distance;
    if (len < 1e-6) return origin;
    return origin + d * (distance / len);
  }

  bool _clockwise(Offset prev, Offset corner, Offset next) {
    final cross = (corner.dx - prev.dx) * (next.dy - corner.dy) -
        (corner.dy - prev.dy) * (next.dx - corner.dx);
    return cross < 0;
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.links != links ||
      old.walkedColour != walkedColour ||
      old.aheadColour != aheadColour ||
      old.walkedThroughLink != walkedThroughLink;
}

/// The empty state: no games yet. A dimmed start node on the spine with a line
/// leading down into nothing, so the screen reads as "your roadmap begins here"
/// rather than as a blank canvas.
class _EmptyRoadmap extends StatelessWidget {
  const _EmptyRoadmap({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topInset + Tokens.space.xl * 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: _kNodeDiameter,
            height: _kNodeDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Tokens.cosmos.panel,
              border: Border.all(color: Tokens.cosmos.panelEdge, width: 2),
            ),
            child: Icon(Icons.add_rounded,
                color: Tokens.palette.text, size: 32),
          ),
          // A short stub of dim path descending from the start node.
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: const Size(5, 56),
              painter: _StubPainter(colour: Tokens.cosmos.trailDim),
            ),
          ),
          SizedBox(height: Tokens.space.md),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Tokens.space.xl),
            child: Text(
              'Add your first game to begin the roadmap',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Tokens.palette.text,
                fontSize: Tokens.type.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: Tokens.space.xs),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Tokens.space.xl),
            child: Text(
              'Each game you save becomes a node on your journey.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.palette.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short vertical dim stub under the empty-state start node.
class _StubPainter extends CustomPainter {
  _StubPainter({required this.colour});
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_StubPainter old) => old.colour != colour;
}
