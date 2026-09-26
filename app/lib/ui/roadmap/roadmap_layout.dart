// The roadmap's geometry, kept PURE on purpose.
//
// Nothing here imports dart:ui drawing, a widget, or a canvas. It turns an
// ordered list of games into node CENTRES on a winding vertical path, plus the
// rounded elbow connector between each pair. The view paints what this returns;
// a unit test on a machine with no GPU asserts the arrangement.
//
// WHY A WINDING PATH, NOT A STRAIGHT COLUMN
//
// The references (Noom Course Map, Mimo Learn) alternate nodes left and right
// of centre and join them with an elbow: a vertical drop, a rounded bend, a
// horizontal run, a second rounded bend, another drop. A straight column reads
// as a list; the alternation is what makes it read as a journey with a shape.
// The connector is therefore never a diagonal -- it is axis-aligned segments
// joined by quarter-circle arcs, which is exactly the "rounded corners and
// straight lines" the design calls for.

import 'dart:math' as math;
import 'dart:ui' show Offset, Path, Size;

/// Which side of the centre line a node sits on.
enum RoadSide { left, centre, right }

/// One placed node: the game's index in the source list, its centre, and side.
class RoadNode {
  const RoadNode({
    required this.index,
    required this.centre,
    required this.side,
  });

  /// Index into the ordered game list this layout was built from.
  final int index;

  /// Centre of the node in canvas pixels, y growing downward.
  final Offset centre;

  final RoadSide side;
}

/// A rounded elbow connector from one node centre toward the next.
///
/// Expressed as an ordered list of points with a corner radius, so the painter
/// can stroke straight segments joined by arcs without re-deriving geometry.
/// Two points means a straight segment (same column); more means an elbow.
class RoadLink {
  const RoadLink({required this.points, required this.radius});

  /// Ordered polyline the stroke follows, corners rounded by [radius].
  final List<Offset> points;

  /// Corner radius in pixels. Clamped so it never exceeds half the shortest
  /// segment, which would make an arc overshoot its own corner.
  final double radius;
}

/// The whole laid-out roadmap: nodes and the links between consecutive nodes.
class RoadmapLayout {
  const RoadmapLayout({
    required this.nodes,
    required this.links,
    required this.size,
  });

  final List<RoadNode> nodes;

  /// One fewer than [nodes]: the connector from node i to node i+1.
  final List<RoadLink> links;

  /// Total scrollable canvas size. Height grows with the node count.
  final Size size;
}

/// Lays out [count] nodes on a winding vertical path.
///
/// The path starts near the top and descends. Nodes alternate right and left of
/// the centre line; the first node sits centred so the journey begins on the
/// spine rather than lurching sideways. Each node is [rowHeight] below the last.
///
/// [width] is the viewport width; [sideInset] is how far a left/right node sits
/// from the centre line. [topInset] / [bottomInset] clear the header and the
/// floating controls so no node hides under chrome. [nodeRadius] is half the
/// node's circular hit area: connectors anchor to the node EDGE (this radius
/// out from the centre) rather than the centre, so the stroke never crosses the
/// card the way a centre-to-centre line did.
RoadmapLayout layoutRoadmap({
  required int count,
  required double width,
  double rowHeight = 168,
  double sideInset = 64,
  double topInset = 0,
  double bottomInset = 0,
  double cornerRadius = 24,
  double nodeRadius = 40,
}) {
  final centreX = width / 2;
  final firstY = topInset + rowHeight * 0.6;

  RoadSide sideFor(int i) {
    if (i == 0) return RoadSide.centre;
    // Alternate right, left, right, ... after the centred first node.
    return i.isOdd ? RoadSide.right : RoadSide.left;
  }

  double xFor(RoadSide s) => switch (s) {
        RoadSide.left => centreX - sideInset,
        RoadSide.centre => centreX,
        RoadSide.right => centreX + sideInset,
      };

  final nodes = <RoadNode>[
    for (var i = 0; i < count; i++)
      RoadNode(
        index: i,
        side: sideFor(i),
        centre: Offset(xFor(sideFor(i)), firstY + i * rowHeight),
      ),
  ];

  final links = <RoadLink>[
    for (var i = 0; i < nodes.length - 1; i++)
      _linkBetween(
        nodes[i].centre,
        nodes[i + 1].centre,
        cornerRadius,
        nodeRadius,
      ),
  ];

  final height = count == 0
      ? topInset + bottomInset + rowHeight
      : firstY + (count - 1) * rowHeight + rowHeight * 0.6 + bottomInset;

  return RoadmapLayout(
    nodes: nodes,
    links: links,
    size: Size(width, height),
  );
}

/// Builds the elbow between two node centres, anchored to the node EDGES.
///
/// The line leaves the FROM node at its bottom edge and enters the TO node at
/// its top edge ([nodeRadius] from each centre vertically), so it never draws
/// across a card. Same column -> a single vertical segment. Different columns ->
/// drop to the midpoint, run across, drop again: a four-point elbow with two
/// rounded corners. Vertical-first keeps the line leaving each node downward.
RoadLink _linkBetween(
  Offset fromCentre,
  Offset toCentre,
  double radius,
  double nodeRadius,
) {
  final from = Offset(fromCentre.dx, fromCentre.dy + nodeRadius);
  final to = Offset(toCentre.dx, toCentre.dy - nodeRadius);
  if ((from.dx - to.dx).abs() < 0.5) {
    return RoadLink(points: [from, to], radius: 0);
  }
  final midY = (from.dy + to.dy) / 2;
  final points = [
    from,
    Offset(from.dx, midY),
    Offset(to.dx, midY),
    to,
  ];
  // Clamp the radius so an arc can never be larger than half of the shortest
  // segment it sits between, or two arcs on one corner would overlap.
  final vLeg = (midY - from.dy).abs();
  final hLeg = (to.dx - from.dx).abs();
  final maxR = math.min(vLeg, hLeg) / 2;
  return RoadLink(points: points, radius: math.min(radius, maxR));
}


/// The first [t] fraction (0..1) of [path]'s length, as a new path.
///
/// Used by the draw-line creation animation: strokes progressively more of a
/// connector as the fraction rises. Pure -- takes a Path, returns a Path -- so
/// the draw mechanism is unit-testable (the returned length is t of the input's)
/// without a canvas or an animation clock.
Path partialPath(Path path, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final out = Path();
  for (final metric in path.computeMetrics()) {
    out.addPath(metric.extractPath(0, metric.length * clamped), Offset.zero);
  }
  return out;
}

/// The total length of [path], summed across its contours.
double pathLength(Path path) {
  var total = 0.0;
  for (final metric in path.computeMetrics()) {
    total += metric.length;
  }
  return total;
}


/// Orders [igdbIds] by their persisted roadmap [order] (igdb_id -> position).
///
/// Games WITH a position come first, in position order. Games WITHOUT one keep
/// their incoming (default) relative order and follow the ordered ones. This is
/// what makes "the user reordered three games" stable while every not-yet-moved
/// game stays where it was, and a brand-new game (no position) lands at the end.
List<int> orderGames(List<int> igdbIds, Map<int, int> order) {
  final ordered = <int>[];
  final rest = <int>[];
  for (final id in igdbIds) {
    (order.containsKey(id) ? ordered : rest).add(id);
  }
  ordered.sort((a, b) => order[a]!.compareTo(order[b]!));
  return [...ordered, ...rest];
}
