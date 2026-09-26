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
    this.justAddedIgdbId,
    this.onAddedDone,
    this.roadmapOrder = const {},
    this.onReorder,
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

  /// The igdbId of a game JUST added, or null. When set and present, the
  /// connector into that node draws progressively, the view follows the drawing
  /// head, and the node pops in at the end. One-shot: [onAddedDone] fires when
  /// the sequence finishes so the caller clears the signal.
  final int? justAddedIgdbId;

  /// Called when the draw-line creation animation finishes.
  final VoidCallback? onAddedDone;

  /// igdb_id -> chosen roadmap position. Games absent fall to the end in their
  /// default order. Used to order the nodes on the path.
  final Map<int, int> roadmapOrder;

  /// Called with the full list of igdb_ids in their new order when the user
  /// finishes a drag-reorder. Null disables reordering.
  final void Function(List<int> igdbIdsInOrder)? onReorder;

  @override
  State<RoadmapView> createState() => _RoadmapViewState();
}

class _RoadmapViewState extends State<RoadmapView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// Drives the connector-draw fraction 0->1 for a just-added node.
  late final AnimationController _draw;

  /// The index of the node currently being drawn in (the just-added one), or
  /// null when nothing is animating. Its incoming link strokes to [_draw].value
  /// and the node itself pops in when the draw completes.
  int? _drawingIndex;

  /// True once the draw has completed and the node should pop in.
  bool _popNode = false;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(vsync: this, duration: Tokens.motion.harvest)
      ..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(RoadmapView old) {
    super.didUpdateWidget(old);
    final added = widget.justAddedIgdbId;
    if (added != null && added != old.justAddedIgdbId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAddSequence(added));
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Draw the incoming connector while following the head, then pop the node.
  ///
  /// Reduced motion collapses the whole thing: the node lands at once, no draw,
  /// no scroll animation -- but [onAddedDone] still fires so the signal clears.
  Future<void> _runAddSequence(int igdbId) async {
    final games = _visible;
    final index = games.indexWhere((g) => g.game.igdbId == igdbId);
    if (index < 0 || !mounted) {
      widget.onAddedDone?.call();
      return;
    }

    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    setState(() {
      _drawingIndex = index;
      _popNode = false;
    });

    // Bring the new node into view first, so the draw happens on screen. The
    // new node is the last one, so scroll to the bottom.
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: reduce ? Duration.zero : Tokens.motion.swap,
        curve: Tokens.motion.easeOut,
      );
    }

    // Draw the connector. For the FIRST node there is no incoming link, so the
    // draw is a no-op and only the pop plays.
    if (!reduce && index > 0) {
      _draw.duration = Tokens.motion.harvest;
      await _draw.forward(from: 0);
    } else {
      _draw.value = 1;
    }

    if (!mounted) return;
    // Pop the node in.
    setState(() => _popNode = true);
    await Future<void>.delayed(reduce ? Duration.zero : Tokens.motion.grow);

    if (!mounted) return;
    setState(() {
      _drawingIndex = null;
      _popNode = false;
      _draw.value = 0;
    });
    widget.onAddedDone?.call();
  }

  /// Games shown on the roadmap, in roadmap order.
  ///
  /// Shelved rows are dropped: the roadmap is the active journey. Ordered by the
  /// persisted roadmap order (games without a position keep their default order,
  /// after the ordered ones) so a user's drag-reorder survives a reload.
  List<TreeItem> get _visible {
    final active =
        widget.items.where((i) => !i.entry.shelved).toList();
    final byId = {for (final i in active) i.game.igdbId: i};
    final ids = orderGames(
        active.map((i) => i.game.igdbId).toList(), widget.roadmapOrder);
    return [for (final id in ids) byId[id]!];
  }

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
                  painter: RoadPainter(
                    links: layout.links,
                    walkedColour: Tokens.cosmos.trail,
                    aheadColour: Tokens.cosmos.trailDim,
                    walkedThroughLink: walked - 1,
                    // The link INTO the drawing node is index-1 (node i's
                    // incoming link is link i-1). While drawing, stroke it to
                    // the draw fraction; -1 disables partial draw.
                    drawingLink: _drawingIndex == null ? -1 : _drawingIndex! - 1,
                    drawProgress: _draw.value,
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

        return SingleChildScrollView(controller: _scroll, child: board);
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

    // While this node's incoming connector is still drawing, keep the node
    // hidden; the moment the draw completes it pops in. A node not being added
    // is simply visible (its arrival pop already played when it first mounted).
    final isDrawingTarget = _drawingIndex == node.index;
    final hidden = isDrawingTarget && !_popNode;

    final nodeWidget = RoadmapNode(
      item: item,
      diameter: d,
      titleSide: titleSide,
      titleWidth: titleWidth,
      // Pop the just-added node in when the draw finishes; other nodes use
      // the view's normal arrival setting.
      animateIn: isDrawingTarget ? _popNode : widget.animateArrivals,
      coverCache: widget.coverCache,
      onCoverFound: widget.onCoverFound,
      onTap: () => widget.onSelect?.call(item),
      // Long-press is the DRAG handle when reordering is on, so it no longer
      // opens the sheet (tap does). onHold stays wired only when reordering is
      // off, preserving the old hold-to-open behaviour on non-editable mounts.
      onLongPress: widget.onReorder != null || widget.onHold == null
          ? null
          : () => widget.onHold!.call(item),
    );

    // Reordering: long-press to pick a node up, drop it on another to move it
    // there. Disabled (plain node) when onReorder is null -- the profile
    // portrait is a picture, not an editor.
    final Widget child = widget.onReorder == null
        ? nodeWidget
        : DragTarget<int>(
            onWillAcceptWithDetails: (d) => d.data != item.game.igdbId,
            onAcceptWithDetails: (d) =>
                _reorderTo(d.data, item.game.igdbId),
            builder: (context, candidate, rejected) => LongPressDraggable<int>(
              data: item.game.igdbId,
              feedback: _dragFeedback(item, d),
              childWhenDragging: Opacity(opacity: 0.3, child: nodeWidget),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: candidate.isNotEmpty
                      ? Tokens.cosmos.glow.withValues(alpha: 0.3)
                      : null,
                ),
                child: nodeWidget,
              ),
            ),
          );

    return Positioned(
      left: rowLeft,
      top: node.centre.dy - d / 2,
      child: Opacity(opacity: hidden ? 0 : 1, child: child),
    );
  }

  /// A small circular preview shown under the finger while dragging a node.
  Widget _dragFeedback(TreeItem item, double d) => Material(
        color: Tokens.palette.bg.withValues(alpha: 0),
        child: SizedBox(
          width: d,
          height: d,
          child: RoadmapNode(
            item: item,
            diameter: d,
            titleSide: NodeTitleSide.right,
            titleWidth: 0,
            onTap: () {},
          ),
        ),
      );

  /// Moves [draggedId] to sit where [targetId] is, then persists the new order.
  void _reorderTo(int draggedId, int targetId) {
    final ids = _visible.map((i) => i.game.igdbId).toList();
    final from = ids.indexOf(draggedId);
    final to = ids.indexOf(targetId);
    if (from < 0 || to < 0 || from == to) return;
    ids.removeAt(from);
    ids.insert(to, draggedId);
    widget.onReorder?.call(ids);
  }
}

/// Strokes the rounded elbow connectors, walked part bright and the rest dim.
///
/// Each link is an axis-aligned polyline with a corner radius. A straight link
/// (two points) is one line; an elbow (four points) is drawn segment by segment
/// with a quarter-circle arc at each interior corner, so the bend is a true
/// rounded corner rather than a chamfer.
class RoadPainter extends CustomPainter {
  RoadPainter({
    required this.links,
    required this.walkedColour,
    required this.aheadColour,
    required this.walkedThroughLink,
    this.drawingLink = -1,
    this.drawProgress = 1,
  });

  final List<RoadLink> links;
  final Color walkedColour;
  final Color aheadColour;

  /// Highest link index that is "walked" (bright). -1 means none are.
  final int walkedThroughLink;

  /// The link currently drawing in (partial stroke), or -1 for none.
  final int drawingLink;

  /// How much of [drawingLink] to stroke, 0..1.
  final double drawProgress;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < links.length; i++) {
      final paint = Paint()
        ..color = i <= walkedThroughLink ? walkedColour : aheadColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final full = _pathFor(links[i]);
      if (i == drawingLink && drawProgress < 1) {
        // Partial stroke: walk the path metric to drawProgress of its length,
        // so the line appears to draw from the from-node toward the new node.
        canvas.drawPath(partialPath(full, drawProgress), paint);
      } else {
        canvas.drawPath(full, paint);
      }
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
  bool shouldRepaint(RoadPainter old) =>
      old.links != links ||
      old.walkedColour != walkedColour ||
      old.aheadColour != aheadColour ||
      old.walkedThroughLink != walkedThroughLink ||
      old.drawingLink != drawingLink ||
      old.drawProgress != drawProgress;
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
