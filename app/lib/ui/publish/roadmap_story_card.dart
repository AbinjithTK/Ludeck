// The shareable story: the collection as its ROADMAP, not a stat line.
//
// This is the Stage 5 enhancement of the old summary card. Instead of "Level N,
// M harvested, one sample title", the shared image now shows the journey the
// way the app does -- a winding path of nodes, each ringed by its status, the
// gold ones lit. A friend who sees it recognises the same roadmap they will get
// when they open the app, which is the whole point of a shareable.
//
// PRIVACY: it renders ONLY `PublishedGame` (title, cover, status, rating,
// branch name). It never touches recommendedBy, notes, or a source's channel --
// there is no such field on the shape it is given, exactly as publish_export
// guarantees. Same invariant the old card held.
//
// It reuses the pure `roadmap_layout` geometry so the shared path is the SAME
// winding shape as the live roadmap, and a static painter (no gestures, no
// network) draws it -- a card is a picture, not a control.

import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../roadmap/roadmap_layout.dart';
import '../tokens.dart';

/// A 4:5 shareable card showing the collection's roadmap journey.
class RoadmapStoryCard extends StatelessWidget {
  const RoadmapStoryCard({
    super.key,
    required this.games,
    required this.level,
  });

  final List<PublishedGame> games;
  final int level;

  @override
  Widget build(BuildContext context) {
    final harvested =
        games.where((g) => g.status == Progress.finished).length;

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: SoftCard(
        deep: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: the level orb and the one-line summary.
            Row(
              children: [
                GlowOrb(diameter: 40, glow: 0.7, child: Text('$level')),
                SizedBox(width: Tokens.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Level $level',
                        style: TextStyle(
                          fontSize: Tokens.type.body,
                          fontWeight: FontWeight.w700,
                          color: Tokens.palette.text,
                        ),
                      ),
                      Text(
                        harvested == 1
                            ? '1 game finished'
                            : '$harvested games finished',
                        style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: Tokens.palette.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Tokens.space.sm),

            // The roadmap itself, filling the card's middle.
            Expanded(
              child: games.isEmpty
                  ? Center(
                      child: Text(
                        'A roadmap waiting to begin.',
                        style: TextStyle(
                          fontSize: Tokens.type.body,
                          color: Tokens.palette.textDim,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _StoryRoadmapPainter(games: games),
                      ),
                    ),
            ),

            SizedBox(height: Tokens.space.xs),
            Text(
              'Ludeck',
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.textDim,
                letterSpacing: Tokens.type.trackingTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a compact winding roadmap for the share card: the same path geometry
/// as the live roadmap, node dots ringed by status, gold ones lit. Static --
/// no covers fetched, no gestures. Caps the node count so a huge collection
/// still fits the card (the story is the shape, not every game).
class _StoryRoadmapPainter extends CustomPainter {
  _StoryRoadmapPainter({required this.games});

  final List<PublishedGame> games;

  /// Most a card shows before it stops adding dots -- beyond this the path is
  /// unreadable at card size, so it shows the first N and the shape they make.
  static const int _cap = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = games.length > _cap ? games.sublist(0, _cap) : games;
    // Fit the winding path into the card: derive a row height that spreads the
    // shown nodes across the available height with a margin.
    final rows = shown.length;
    final usableH = size.height - 24;
    final rowHeight = rows <= 1 ? usableH : usableH / (rows - 1);
    const nodeRadius = 12.0;

    final layout = layoutRoadmap(
      count: rows,
      width: size.width,
      rowHeight: rowHeight,
      sideInset: size.width * 0.18,
      topInset: 12,
      cornerRadius: 10,
      nodeRadius: nodeRadius,
    );

    // Connectors first, behind the dots. All bright: a shared story is a
    // finished artifact, not a progress tracker with an "ahead" section.
    for (final link in layout.links) {
      final paint = Paint()
        ..color = Tokens.cosmos.trail
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_pathFor(link), paint);
    }

    // Node dots, ringed by status.
    for (var i = 0; i < layout.nodes.length; i++) {
      final node = layout.nodes[i];
      final g = shown[i];
      final finished = g.status == Progress.finished;
      final ringColour =
          finished ? Tokens.palette.accent : Tokens.cosmos.panelEdge;

      if (finished) {
        // The gold glow that marks a harvested game.
        canvas.drawCircle(
          node.centre,
          nodeRadius + 3,
          Paint()
            ..color = Tokens.palette.accent.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(
        node.centre,
        nodeRadius,
        Paint()..color = Tokens.cosmos.panelDeep,
      );
      canvas.drawCircle(
        node.centre,
        nodeRadius,
        Paint()
          ..color = ringColour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
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
      final before = _towards(corner, prev, r);
      final after = _towards(corner, next, r);
      path.lineTo(before.dx, before.dy);
      path.arcToPoint(
        after,
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
  bool shouldRepaint(_StoryRoadmapPainter old) => old.games != games;
}
