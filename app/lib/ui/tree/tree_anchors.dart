// GENERATED FILE. Do not edit by hand.
//
// Produced by rive/tree/gen_anchors.ps1 from rive/tree/scene.rml.
// Re-run it after moving any branch:
//   powershell -File rive/tree/gen_anchors.ps1
//
// A branch in the RML is a closed path: out along one edge to the tip and back
// along the other. So its centreline is the midpoint of each corresponding pair
// of vertices, and these anchors are sampled at even arc lengths along it.
//
// Anchors stop short of both ends on purpose. A fruit near the trunk reads as a
// growth on the trunk, and a fruit exactly on the tip looks about to fall off.
library;

import 'dart:ui';

/// The artboard size every coordinate below is expressed in.
const Size kTreeArtboardSize = Size(400, 560);

/// One place a fruit can hang.
class BranchAnchor {
  const BranchAnchor({
    required this.position,
    required this.depth,
    required this.branch,
  });

  /// In artboard space.
  final Offset position;

  /// 0 is the back layer, 1 the front. Fruit inherit their branch depth, so a
  /// fruit on a back branch is drawn smaller and dimmer. Without this, fruit
  /// would flatten the depth the artboard just built.
  final double depth;

  /// The RML shape this belongs to, so a diff against the artwork is readable.
  final String branch;
}

/// Front layer first.
const List<BranchAnchor> kBranchAnchors = [
  BranchAnchor(position: Offset(39.6, 262.6), depth: 1.00, branch: 'BranchFrontLeft'),
  BranchAnchor(position: Offset(79.2, 298.8), depth: 1.00, branch: 'BranchFrontLeft'),
  BranchAnchor(position: Offset(125.8, 325.9), depth: 1.00, branch: 'BranchFrontLeft'),
  BranchAnchor(position: Offset(347.4, 213.2), depth: 1.00, branch: 'BranchFrontRight'),
  BranchAnchor(position: Offset(312.8, 252.4), depth: 1.00, branch: 'BranchFrontRight'),
  BranchAnchor(position: Offset(271.1, 284.4), depth: 1.00, branch: 'BranchFrontRight'),
  BranchAnchor(position: Offset(217.4, 115.9), depth: 0.80, branch: 'BranchLeader'),
  BranchAnchor(position: Offset(107.3, 145.2), depth: 0.60, branch: 'BranchMidLeft'),
  BranchAnchor(position: Offset(126.1, 186.8), depth: 0.60, branch: 'BranchMidLeft'),
  BranchAnchor(position: Offset(150.1, 225.8), depth: 0.60, branch: 'BranchMidLeft'),
  BranchAnchor(position: Offset(282.5, 114.4), depth: 0.60, branch: 'BranchMidRight'),
  BranchAnchor(position: Offset(266.6, 153.4), depth: 0.60, branch: 'BranchMidRight'),
  BranchAnchor(position: Offset(245.6, 190.1), depth: 0.60, branch: 'BranchMidRight'),
  BranchAnchor(position: Offset(134, 96), depth: 0.25, branch: 'BranchBackLeft'),
  BranchAnchor(position: Offset(159.6, 163.5), depth: 0.25, branch: 'BranchBackLeft'),
  BranchAnchor(position: Offset(259.9, 77.6), depth: 0.25, branch: 'BranchBackRight'),
  BranchAnchor(position: Offset(238.3, 141.5), depth: 0.25, branch: 'BranchBackRight'),
];

/// Where a seed sits. Seeds are spotted, not owned, so they are not on a branch
/// at all; they rest in the soil and may rest there forever without reproach.
const List<Offset> kSoilAnchors = [
  Offset(150, 498),
  Offset(182, 506),
  Offset(224, 504),
  Offset(256, 497),
];

/// Fruit radius in artboard space, by depth. A fruit on a back branch is
/// genuinely smaller, not just dimmer, because size is the stronger cue.
double fruitRadiusForDepth(double depth) => 8 + (depth * 5);
