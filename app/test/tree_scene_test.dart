import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/tree/tree_anchors.dart';
import 'package:ludeck/ui/tree/tree_scene.dart';

/// The parallax is what makes a flat scene read as having depth, and it is pure
/// arithmetic, so it is testable without a device. That matters here because a
/// mid-drag screenshot could not be captured on this machine: the window would
/// not come frontmost for a synthetic drag.
///
/// These tests assert the RELATIONSHIPS between layers, not specific pixel
/// values. The magnitudes are tuned by eye and will change; the relationships
/// are the design and must not.
void main() {
  const scale = 1.0;

  group('at rest nothing is displaced', () {
    test('every layer sits at zero when rotation is zero', () {
      for (final layer in kTreeLayers) {
        expect(parallaxOffsetFor(layer.artboard, 0, scale), 0,
            reason: '${layer.artboard} must be still at rest');
      }
    });

    test('the trunk is not squeezed at rest', () {
      expect(trunkSqueezeFor(0), 1.0);
    });
  });

  group('the trunk is the pivot', () {
    test('the trunk never translates, at any rotation', () {
      for (final r in [-1.0, -0.5, 0.25, 0.8, 1.0]) {
        expect(parallaxOffsetFor('TreeTrunk', r, scale), 0,
            reason: 'the trunk is the pivot and must not slide');
      }
    });

    test('the trunk narrows as it turns, in both directions', () {
      expect(trunkSqueezeFor(1.0), lessThan(1.0));
      expect(trunkSqueezeFor(-1.0), lessThan(1.0));
      expect(trunkSqueezeFor(1.0), closeTo(trunkSqueezeFor(-1.0), 1e-9),
          reason: 'turning left and right must foreshorten equally');
    });

    test('the squeeze is subtle, never a visible distortion', () {
      expect(trunkSqueezeFor(1.0), greaterThan(0.9));
    });
  });

  group('near and far move in opposite directions', () {
    test('the front layer follows the finger', () {
      expect(parallaxOffsetFor('TreeFront', 1.0, scale), greaterThan(0));
    });

    test('the back layer moves against it', () {
      expect(parallaxOffsetFor('TreeBack', 1.0, scale), lessThan(0),
          reason: 'counter-movement is the parallax cue; without it this is '
              'just a slide');
    });

    test('the mid layer moves against it, but less than the back', () {
      final mid = parallaxOffsetFor('TreeMid', 1.0, scale);
      final back = parallaxOffsetFor('TreeBack', 1.0, scale);
      expect(mid, lessThan(0));
      expect(mid.abs(), lessThan(back.abs()),
          reason: 'the mid layer is nearer than the back layer');
    });

    test('the front layer moves further than anything else', () {
      final front = parallaxOffsetFor('TreeFront', 1.0, scale).abs();
      for (final layer in kTreeLayers) {
        if (layer.artboard == 'TreeFront') continue;
        expect(parallaxOffsetFor(layer.artboard, 1.0, scale).abs(),
            lessThan(front),
            reason: '${layer.artboard} must not out-travel the front layer');
      }
    });
  });

  group('the ground anchors the scene', () {
    test('the ground barely moves', () {
      final ground = parallaxOffsetFor('TreeGround', 1.0, scale).abs();
      final front = parallaxOffsetFor('TreeFront', 1.0, scale).abs();
      expect(ground, lessThan(front * 0.2),
          reason: 'a floor that slides destroys the illusion faster than '
              'anything else here');
    });
  });

  group('displacement is linear and symmetric', () {
    test('doubling the rotation doubles the offset', () {
      final half = parallaxOffsetFor('TreeFront', 0.5, scale);
      final full = parallaxOffsetFor('TreeFront', 1.0, scale);
      expect(full, closeTo(half * 2, 1e-9));
    });

    test('rotating the other way mirrors exactly', () {
      for (final layer in kTreeLayers) {
        expect(parallaxOffsetFor(layer.artboard, -1.0, scale),
            closeTo(-parallaxOffsetFor(layer.artboard, 1.0, scale), 1e-9));
      }
    });

    test('offsets scale with the canvas, so the effect holds on any screen', () {
      final small = parallaxOffsetFor('TreeFront', 1.0, 1.0);
      final large = parallaxOffsetFor('TreeFront', 1.0, 3.0);
      expect(large, closeTo(small * 3, 1e-9));
    });
  });

  group('anchors are generated from the artwork', () {
    test('every anchor is inside the artboard', () {
      for (final a in kBranchAnchors) {
        expect(a.position.dx, inInclusiveRange(0, kTreeArtboardSize.width));
        expect(a.position.dy, inInclusiveRange(0, kTreeArtboardSize.height));
      }
    });

    test('every anchor names a branch that maps to a real layer', () {
      final names = kTreeLayers.map((l) => l.artboard).toSet();
      for (final a in kBranchAnchors) {
        expect(names, contains(layerForBranch(a.branch)));
      }
    });

    test('a fruit on a back branch is smaller than one at the front', () {
      expect(fruitRadiusForDepth(0.25), lessThan(fruitRadiusForDepth(1.0)),
          reason: 'size is the stronger depth cue, so it must not be flat');
    });

    test('there are enough anchors for a starting collection', () {
      expect(kBranchAnchors.length, greaterThanOrEqualTo(10));
    });

    test('front branches come first, so early games read best', () {
      expect(layerForBranch(kBranchAnchors.first.branch), 'TreeFront');
    });

    test('seeds rest in the soil, below the branches', () {
      final lowestAnchor =
          kBranchAnchors.map((a) => a.position.dy).reduce((a, b) => a > b ? a : b);
      for (final s in kSoilAnchors) {
        expect(s.dy, greaterThan(lowestAnchor),
            reason: 'a seed is not on a branch; it sits in the ground');
      }
    });
  });
}
