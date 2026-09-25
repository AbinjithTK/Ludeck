// Invariants for the tree's mesh construction.
//
// Pure unit tests on purpose: no `testWidgets`, no database, no GPU. The whole
// reason `tree_mesh.dart` holds no flutter_scene import is so these run on the
// same headless Windows machine the rest of the suite does.
//
// What these tests are FOR: `TubeGeometry` sweeps one scalar radius, so it
// cannot express a tapered trunk, and a constant-radius tube rendering fine
// would be a false pass for the 3D port. These assert the taper actually
// survives into vertex positions, that the surface is closed, and that the frame
// does not twist on the curving limbs the engine deliberately generates.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/tree/procedural_tree.dart';
import 'package:ludeck/ui/tree/tree_mesh.dart';
import 'package:vector_math/vector_math.dart' as vm;

const Size _canvas = Size(412, 760);

TreeItem _item(int id, String title, {Progress progress = Progress.playing}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: progress,
      ),
      copies: const [],
    );

ProceduralTree _tree({
  List<Branch> branches = const [],
  Map<int, List<int>> placements = const {},
  int games = 6,
}) =>
    ProceduralTree.build(
      canvas: _canvas,
      branches: branches,
      placements: placements,
      items: [
        for (var i = 1; i <= games; i++) _item(i, 'Game $i'),
      ],
      fruitRadius: 28,
      trunkWidth: 26,
    );

/// A straight vertical spine with a linear taper, for the arithmetic cases.
({List<vm.Vector3> spine, List<double> radii}) _cone({int samples = 9}) => (
      spine: [
        for (var i = 0; i < samples; i++) vm.Vector3(0, i / (samples - 1) * 4, 0),
      ],
      radii: [
        for (var i = 0; i < samples; i++) 0.30 - 0.25 * (i / (samples - 1)),
      ],
    );

void main() {
  group('canvas to scene mapping', () {
    test('centres x on the canvas so the trunk stands at the origin', () {
      final mid = canvasToScene(const Offset(206, 0), _canvas);
      expect(mid.x, closeTo(0, 1e-9));
    });

    test('flips y, because canvas y grows down and scene y grows up', () {
      final ground = canvasToScene(const Offset(206, 760), _canvas);
      final sky = canvasToScene(const Offset(206, 0), _canvas);
      expect(ground.y, closeTo(0, 1e-9));
      expect(sky.y, greaterThan(ground.y));
      // vector_math stores components in a Float32List, so 7.6 comes back as
      // 7.599999904632568. Tolerance is float32 epsilon, not a loosened
      // assertion -- the other cases here hold to 1e-9 only because 0 and 1.0
      // are exactly representable.
      expect(sky.y, closeTo(7.6, 1e-5));
    });

    test('scales by pixels per metre rather than shipping raw pixels', () {
      final p = canvasToScene(const Offset(306, 660), _canvas);
      expect(p.x, closeTo(1.0, 1e-9));
      expect(p.y, closeTo(1.0, 1e-9));
    });
  });

  group('tapered tube construction', () {
    test('emits one ring per spine sample', () {
      final c = _cone(samples: 9);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 10,
      );
      expect(mesh.ringCount, 9);
      expect(mesh.vertexCount, 9 * 10);
      expect(mesh.normals.length, mesh.vertexCount);
      expect(mesh.uvs.length, mesh.vertexCount);
    });

    test('stitches every ring pair into two triangles per segment', () {
      final c = _cone(samples: 5);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 8,
      );
      expect(mesh.triangleCount, (5 - 1) * 8 * 2);
    });

    test('every index addresses a real vertex', () {
      final c = _cone();
      final mesh = buildTaperedTube(spine: c.spine, radii: c.radii);
      expect(mesh.indices, isNotEmpty);
      for (final i in mesh.indices) {
        expect(i, greaterThanOrEqualTo(0));
        expect(i, lessThan(mesh.vertexCount));
      }
    });

    test('no triangle is degenerate', () {
      final c = _cone();
      final mesh = buildTaperedTube(spine: c.spine, radii: c.radii);
      for (var t = 0; t < mesh.indices.length; t += 3) {
        final a = mesh.indices[t];
        final b = mesh.indices[t + 1];
        final cc = mesh.indices[t + 2];
        expect({a, b, cc}.length, 3, reason: 'triangle $t repeats a vertex');
        final area = (mesh.positions[b] - mesh.positions[a])
                .cross(mesh.positions[cc] - mesh.positions[a])
                .length /
            2;
        expect(area, greaterThan(1e-9), reason: 'triangle $t has no area');
      }
    });

    test('the surface is closed: the last radial segment wraps to the first',
        () {
      final c = _cone(samples: 3);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 6,
      );
      // Every interior edge must be shared by exactly two triangles, which is
      // only true if the ring wraps rather than leaving a seam.
      final edgeUse = <String, int>{};
      for (var t = 0; t < mesh.indices.length; t += 3) {
        final tri = [
          mesh.indices[t],
          mesh.indices[t + 1],
          mesh.indices[t + 2],
        ];
        for (var e = 0; e < 3; e++) {
          final u = tri[e];
          final v = tri[(e + 1) % 3];
          final key = u < v ? '$u-$v' : '$v-$u';
          edgeUse[key] = (edgeUse[key] ?? 0) + 1;
        }
      }
      // An open tube has exactly radialSegments boundary edges per end cap.
      final boundary = edgeUse.values.where((n) => n == 1).length;
      expect(boundary, 6 * 2,
          reason: 'a closed tube has boundary edges only at its two ends');
    });

    // THE test this file exists for.
    test('radius per sample survives into vertex positions', () {
      final c = _cone(samples: 9);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 12,
      );
      for (var ring = 0; ring < mesh.ringCount; ring++) {
        final centre = c.spine[ring];
        for (var s = 0; s < mesh.radialSegments; s++) {
          final p = mesh.positions[ring * mesh.radialSegments + s];
          expect((p - centre).length, closeTo(c.radii[ring], 1e-6),
              reason: 'ring $ring vertex $s sits at the wrong radius');
        }
      }
    });

    test('a tapering stem is genuinely narrower at the tip than the base', () {
      final c = _cone(samples: 9);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 12,
      );
      double ringRadius(int ring) =>
          (mesh.positions[ring * mesh.radialSegments] - c.spine[ring]).length;
      expect(ringRadius(mesh.ringCount - 1), lessThan(ringRadius(0) * 0.5),
          reason: 'this is exactly what TubeGeometry cannot express');
    });

    test('normals are unit length and perpendicular to the spine direction',
        () {
      final c = _cone();
      final mesh = buildTaperedTube(spine: c.spine, radii: c.radii);
      final up = vm.Vector3(0, 1, 0);
      for (final n in mesh.normals) {
        expect(n.length, closeTo(1, 1e-6));
        expect(n.dot(up).abs(), lessThan(1e-6),
            reason: 'a straight vertical stem has purely horizontal normals');
      }
    });

    test('texture coordinates span 0..1 along the spine', () {
      final c = _cone(samples: 5);
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 4,
      );
      expect(mesh.uvs.first.y, closeTo(0, 1e-9));
      expect(mesh.uvs.last.y, closeTo(1, 1e-9));
      expect(mesh.uvs.map((u) => u.x).reduce(math.max), lessThan(1.0));
    });

    test('consecutive duplicate spine points are dropped, not turned into '
        'a zero-length segment', () {
      final mesh = buildTaperedTube(
        spine: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(0, 0, 0),
          vm.Vector3(0, 1, 0),
          vm.Vector3(0, 2, 0),
        ],
        radii: const [0.2, 0.2, 0.15, 0.1],
        radialSegments: 6,
      );
      expect(mesh.ringCount, 3);
      for (final p in mesh.positions) {
        expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue);
      }
    });

    test('rejects mismatched or unusable input rather than emitting a bad mesh',
        () {
      expect(
        () => buildTaperedTube(
          spine: [vm.Vector3(0, 0, 0), vm.Vector3(0, 1, 0)],
          radii: const [0.2],
        ),
        throwsArgumentError,
      );
      expect(
        () => buildTaperedTube(
          spine: [vm.Vector3(0, 0, 0), vm.Vector3(0, 1, 0)],
          radii: const [0.2, 0.1],
          radialSegments: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildTaperedTube(
          spine: [vm.Vector3(0, 0, 0)],
          radii: const [0.2],
        ),
        throwsArgumentError,
      );
    });
  });

  group('frames do not twist on a curving stem', () {
    // HONEST SCOPE. I tried to show a fixed up-vector projection failing on
    // Ludeck's own limb shapes and could NOT: a limb that arcs in the xy plane,
    // and one that leans into depth by the amount `depthSpan` actually allows,
    // both come out the same either way. A fixed seed axis only breaks where the
    // tangent swings toward the seed axis ITSELF -- there the cross product
    // collapses to zero length and the frame is undefined. So these tests are
    // protection for a future where depth drives a larger z span or a stem
    // genuinely heads into the camera, not a fix for a defect visible today.
    // Rotation-minimizing transport is kept because it is unconditionally
    // correct and costs one reflection per sample; the naive form is a
    // correctness cliff with no warning on it.
    double worstRoll(TubeMesh mesh, List<vm.Vector3> spine) {
      var worst = 0.0;
      for (var ring = 1; ring < mesh.ringCount; ring++) {
        final prev = (mesh.positions[(ring - 1) * mesh.radialSegments] -
                spine[ring - 1])
            .normalized();
        final curr =
            (mesh.positions[ring * mesh.radialSegments] - spine[ring])
                .normalized();
        worst = math.max(worst, math.acos(prev.dot(curr).clamp(-1.0, 1.0)));
      }
      return worst;
    }

    /// Rises, then bends until it travels straight along +z -- i.e. straight at
    /// the camera. The tangent passes exactly through the (0,0,1) seed axis.
    ({List<vm.Vector3> spine, List<double> radii}) intoTheCamera({
      int samples = 20,
    }) {
      final spine = <vm.Vector3>[];
      final radii = <double>[];
      for (var i = 0; i < samples; i++) {
        final u = i / (samples - 1);
        final t = u * (math.pi / 2);
        spine.add(vm.Vector3(0, math.sin(t) * 2, (1 - math.cos(t)) * 2));
        radii.add(0.2 - 0.14 * u);
      }
      return (spine: spine, radii: radii);
    }

    test('a stem that turns to head at the camera produces a finite, '
        'untwisted mesh', () {
      final c = intoTheCamera();
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 12,
      );

      // A fixed seed axis yields NaN at the sample whose tangent IS the seed,
      // which propagates through every position on that ring.
      for (final p in mesh.positions) {
        expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue,
            reason: 'a degenerate frame leaked NaN into the mesh');
      }
      for (final n in mesh.normals) {
        expect(n.length, closeTo(1, 1e-5));
      }
      expect(worstRoll(mesh, c.spine), lessThan(8 * math.pi / 180));
    });

    test('normals stay perpendicular to the stem along a curving spine', () {
      final c = intoTheCamera();
      final mesh = buildTaperedTube(
        spine: c.spine,
        radii: c.radii,
        radialSegments: 8,
      );
      for (var ring = 0; ring < mesh.ringCount; ring++) {
        // Local tangent from the neighbouring samples.
        final a = ring == 0 ? c.spine[0] : c.spine[ring - 1];
        final b = ring == mesh.ringCount - 1
            ? c.spine[ring]
            : c.spine[ring + 1];
        final tangent = (b - a).normalized();
        for (var s = 0; s < mesh.radialSegments; s++) {
          final n = mesh.normals[ring * mesh.radialSegments + s];
          expect(n.dot(tangent).abs(), lessThan(0.05),
              reason: 'ring $ring vertex $s: normal is not on the ring plane');
        }
      }
    });
  });

  group('whole-tree meshes', () {
    test('every stem the engine emits becomes a mesh', () {
      final tree = _tree(
        branches: const [
          (id: 1, name: 'Finished', sortOrder: 0),
          (id: 2, name: 'Playing', sortOrder: 1),
        ],
        placements: const {
          1: [1, 2],
          2: [3],
        },
        games: 6,
      );
      final meshes = buildTreeMeshes(tree);
      expect(meshes.length, 1 + tree.limbs.length + tree.crown.length);
      for (final m in meshes) {
        expect(m.vertexCount, greaterThan(0));
        expect(m.triangleCount, greaterThan(0));
      }
    });

    test('the zero-branch tree -- every new user -- still yields wood', () {
      final meshes = buildTreeMeshes(_tree(games: 8));
      expect(meshes.length, greaterThan(1),
          reason: 'the crown must exist with no branches named');
    });

    test('the trunk mesh is thicker at its base than at its apex', () {
      final tree = _tree(games: 8);
      final spine = stemSpineToScene(tree.trunk, tree.canvas);
      final radii = stemRadii(tree.trunk);
      final mesh = buildTaperedTube(spine: spine, radii: radii);
      final base = (mesh.positions[0] - spine[0]).length;
      final apex = (mesh.positions[(mesh.ringCount - 1) * mesh.radialSegments] -
              spine[mesh.ringCount - 1])
          .length;
      expect(base, greaterThan(apex));
    });

    test('depth becomes a real z axis rather than being discarded', () {
      final tree = _tree(
        branches: const [
          (id: 1, name: 'Finished', sortOrder: 0),
          (id: 2, name: 'Playing', sortOrder: 1),
          (id: 3, name: 'Next up', sortOrder: 2),
        ],
        placements: const {
          1: [1],
          2: [2],
          3: [3],
        },
        games: 6,
      );
      final zs = <double>{};
      for (final limb in tree.limbs) {
        zs.add(stemSpineToScene(limb.stem, tree.canvas, depth: limb.depth)
            .first
            .z);
      }
      expect(zs.length, greaterThan(1),
          reason: 'limbs at different depths must not be coplanar');
    });

    test('a tree is deterministic: the same collection gives the same mesh', () {
      final a = buildTreeMeshes(_tree(games: 7));
      final b = buildTreeMeshes(_tree(games: 7));
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].vertexCount, b[i].vertexCount);
        for (var v = 0; v < a[i].vertexCount; v++) {
          expect((a[i].positions[v] - b[i].positions[v]).length,
              lessThan(1e-9));
        }
      }
    });

    test('meshes come back sorted back to front, so a renderer that cannot '
        'depth-sort still looks right', () {
      final tree = _tree(
        branches: const [
          (id: 1, name: 'Finished', sortOrder: 0),
          (id: 2, name: 'Playing', sortOrder: 1),
          (id: 3, name: 'Next up', sortOrder: 2),
          (id: 4, name: 'Someday', sortOrder: 3),
        ],
        placements: const {
          1: [1],
          2: [2],
          3: [3],
          4: [4],
        },
        games: 8,
      );
      final meshes = buildTreeMeshes(tree);
      // Reconstruct each mesh's z from its first vertex ring centre; sorted
      // ascending by depth means z ascends too.
      final zs = [for (final m in meshes) m.positions.first.z];
      final sorted = [...zs]..sort();
      expect(zs, sorted);
    });
  });
}
