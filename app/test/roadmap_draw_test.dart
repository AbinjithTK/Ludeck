// The draw-line creation animation's GEOMETRY, checkably. A headless widget
// test cannot reliably freeze the animation mid-frame, so these prove the two
// things that actually decide whether the draw looks right:
//   1. partialPath returns exactly t of a path's length, and grows with t --
//      so the connector draws progressively from the from-node.
//   2. links anchor to node EDGES (nodeRadius from each centre), not centres --
//      so the stroke never crosses a node card.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/roadmap/roadmap_layout.dart';

void main() {
  test('partialPath returns t of the full length', () {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 100); // length 100
    expect(pathLength(path), closeTo(100, 0.001));
    expect(pathLength(partialPath(path, 0.0)), closeTo(0, 0.001));
    expect(pathLength(partialPath(path, 0.5)), closeTo(50, 0.5));
    expect(pathLength(partialPath(path, 1.0)), closeTo(100, 0.001));
  });

  test('partialPath grows monotonically with t', () {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0)
      ..lineTo(100, 100);
    var last = -1.0;
    for (final t in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
      final len = pathLength(partialPath(path, t));
      expect(len, greaterThanOrEqualTo(last),
          reason: 'draw fraction $t should not shrink the drawn length');
      last = len;
    }
  });

  test('partialPath clamps out-of-range t', () {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 40);
    expect(pathLength(partialPath(path, -1)), closeTo(0, 0.001));
    expect(pathLength(partialPath(path, 5)), closeTo(40, 0.001));
  });

  test('links anchor to node edges, not centres', () {
    // Two nodes, nodeRadius 40. The link between them must start 40px BELOW the
    // first centre and end 40px ABOVE the second, so the stroke leaves/enters at
    // the circle edge rather than crossing the card.
    const nodeRadius = 40.0;
    final layout = layoutRoadmap(
      count: 2,
      width: 400,
      rowHeight: 168,
      nodeRadius: nodeRadius,
    );
    final a = layout.nodes[0].centre;
    final b = layout.nodes[1].centre;
    final link = layout.links.single;

    expect(link.points.first.dy, closeTo(a.dy + nodeRadius, 0.001),
        reason: 'the link leaves the first node at its bottom edge');
    expect(link.points.last.dy, closeTo(b.dy - nodeRadius, 0.001),
        reason: 'the link enters the second node at its top edge');
  });

  test('a straight (same-column) link is two points, an elbow is four', () {
    // Node 0 is centred, node 1 is to the right -> the first link is an elbow.
    final layout = layoutRoadmap(count: 2, width: 400, nodeRadius: 40);
    expect(layout.links.single.points.length, 4,
        reason: 'centre -> right is an elbow');
  });
}
