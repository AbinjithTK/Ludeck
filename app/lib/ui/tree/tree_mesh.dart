// Mesh construction for the procedural tree, kept PURE on purpose.
//
// Nothing here imports flutter_scene, flutter_gpu or dart:ui drawing. It turns
// a `TreeStem` -- the engine's spine polyline plus its per-sample half-width --
// into plain vertex, normal, texture-coordinate and index lists. The GPU-facing
// adapter that feeds those lists to a `GeometryBuilder` lives beside the scene
// view, so this file is unit-testable on a machine with no GPU at all, which is
// where the test suite actually runs.
//
// WHY THIS EXISTS AT ALL
//
// flutter_scene 0.23.0 ships `TubeGeometry(path, radius:, stations:)`, which
// sweeps a circle of ONE scalar radius along a path. A `TreeStem` carries
// `halfWidth` per spine sample and the taper is the whole reason the painted
// tree stopped reading as a chess pawn: `tree_painter.dart` records that a
// linear taper is a cone. There is no per-station radius anywhere in the
// package's swept-geometry API -- `PolylineGeometry` tapers but is a flat
// ribbon, not a tube -- so a tapered trunk has to be built ring by ring. That
// is this file. It is the correction to the handoff's claim that the 3D port is
// "mostly adding a z axis".

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math.dart' as vm;

import 'procedural_tree.dart';

/// Canvas pixels per scene metre.
///
/// The engine works in layout pixels with y DOWN (Flutter's convention); a
/// scene works in metres with y UP. 100 keeps a phone-height tree around 7.6
/// metres tall, which sits comfortably in a perspective camera's near/far range
/// without scaling the camera to compensate.
const double kPixelsPerMetre = 100;

/// Converts one canvas point into scene space.
///
/// x is centred on the canvas so the trunk stands at the world origin rather
/// than off to one side, and y is flipped because canvas y grows downward while
/// scene y grows upward.
vm.Vector3 canvasToScene(
  Offset p,
  Size canvas, {
  double z = 0,
  double pixelsPerMetre = kPixelsPerMetre,
}) =>
    vm.Vector3(
      (p.dx - canvas.width / 2) / pixelsPerMetre,
      (canvas.height - p.dy) / pixelsPerMetre,
      z / pixelsPerMetre,
    );

/// A stem's spine in scene space.
///
/// `depth` is the 0..1 field the engine already populates to drive scale and
/// shading in 2D; passing it here is what turns the existing, already-tested
/// depth ordering into a real z axis instead of inventing one.
List<vm.Vector3> stemSpineToScene(
  TreeStem stem,
  Size canvas, {
  double depth = 0,
  double depthSpan = 60,
  double pixelsPerMetre = kPixelsPerMetre,
}) {
  final z = (depth - 0.5) * 2 * depthSpan;
  return [
    for (final p in stem.spine)
      canvasToScene(p, canvas, z: z, pixelsPerMetre: pixelsPerMetre),
  ];
}

/// A stem's per-sample radii in scene metres.
List<double> stemRadii(
  TreeStem stem, {
  double pixelsPerMetre = kPixelsPerMetre,
}) =>
    [for (final w in stem.halfWidth) w / pixelsPerMetre];

/// Vertex data for one swept tube, ready to hand to a geometry builder.
///
/// Indices address [positions] and describe triangles in counter-clockwise
/// winding when viewed from outside the tube.
class TubeMesh {
  const TubeMesh({
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.radialSegments,
    required this.ringCount,
  });

  final List<vm.Vector3> positions;
  final List<vm.Vector3> normals;
  final List<vm.Vector2> uvs;
  final List<int> indices;

  /// Vertices around one ring. A ring is not closed by a duplicate vertex; the
  /// last segment wraps to index 0 of the same ring.
  final int radialSegments;

  /// Rings along the spine -- one per surviving spine sample.
  final int ringCount;

  int get vertexCount => positions.length;
  int get triangleCount => indices.length ~/ 3;
}

/// Builds a tube that genuinely tapers, ring by ring along [spine].
///
/// [radii] must be parallel to [spine]: one radius per sample. Consecutive
/// duplicate spine points are dropped, because a zero-length segment has no
/// tangent and the engine's sampled polylines can legitimately repeat a point
/// at a stem's base.
///
/// Frames are carried along the spine by the rotation-minimizing double
/// reflection method rather than projected from a fixed up-vector. A fixed
/// up-vector is cheaper but makes the ring spin about the tangent wherever the
/// path curves hard, and Ludeck's limbs are built specifically to curve -- they
/// leave the trunk near-horizontal and finish near-upright, which is exactly
/// the case that twists.
TubeMesh buildTaperedTube({
  required List<vm.Vector3> spine,
  required List<double> radii,
  int radialSegments = 12,
}) {
  if (spine.length != radii.length) {
    throw ArgumentError(
      'spine (${spine.length}) and radii (${radii.length}) must be parallel',
    );
  }
  if (radialSegments < 3) {
    throw ArgumentError('radialSegments must be at least 3, got $radialSegments');
  }

  // Drop consecutive duplicates, keeping each survivor's own radius.
  final pts = <vm.Vector3>[];
  final rs = <double>[];
  for (var i = 0; i < spine.length; i++) {
    if (pts.isEmpty || (spine[i] - pts.last).length > 1e-9) {
      pts.add(spine[i]);
      rs.add(radii[i]);
    }
  }
  if (pts.length < 2) {
    throw ArgumentError(
      'a tube needs at least two distinct spine points, got ${pts.length}',
    );
  }

  final tangents = <vm.Vector3>[
    for (var i = 0; i < pts.length; i++)
      (i == 0
              ? pts[1] - pts[0]
              : i == pts.length - 1
                  ? pts[i] - pts[i - 1]
                  : pts[i + 1] - pts[i - 1])
          .normalized(),
  ];

  // Seed the first frame from any axis not parallel to the tangent.
  final t0 = tangents.first;
  final seed = t0.z.abs() < 0.9 ? vm.Vector3(0, 0, 1) : vm.Vector3(1, 0, 0);
  var normal = t0.cross(seed).normalized();

  final positions = <vm.Vector3>[];
  final normals = <vm.Vector3>[];
  final uvs = <vm.Vector2>[];

  for (var i = 0; i < pts.length; i++) {
    if (i > 0) {
      normal = _transport(
        normal,
        from: pts[i - 1],
        to: pts[i],
        tangentFrom: tangents[i - 1],
        tangentTo: tangents[i],
      );
    }
    final binormal = tangents[i].cross(normal).normalized();
    final v = pts.length == 1 ? 0.0 : i / (pts.length - 1);

    for (var s = 0; s < radialSegments; s++) {
      final a = (s / radialSegments) * 2 * math.pi;
      final n = (normal * math.cos(a) + binormal * math.sin(a)).normalized();
      normals.add(n);
      uvs.add(vm.Vector2(s / radialSegments, v));
      positions.add(pts[i] + n * rs[i]);
    }
  }

  final indices = <int>[];
  for (var i = 0; i < pts.length - 1; i++) {
    for (var s = 0; s < radialSegments; s++) {
      final next = (s + 1) % radialSegments;
      final a = i * radialSegments + s;
      final b = i * radialSegments + next;
      final c = (i + 1) * radialSegments + next;
      final d = (i + 1) * radialSegments + s;
      indices.addAll([a, b, c, a, c, d]);
    }
  }

  return TubeMesh(
    positions: positions,
    normals: normals,
    uvs: uvs,
    indices: indices,
    radialSegments: radialSegments,
    ringCount: pts.length,
  );
}

/// One step of rotation-minimizing frame transport (Wang et al., double
/// reflection). Reflects the frame across the plane between the two points,
/// then across the plane between the two tangents, which carries the frame with
/// the minimum possible twist about the tangent.
vm.Vector3 _transport(
  vm.Vector3 normal, {
  required vm.Vector3 from,
  required vm.Vector3 to,
  required vm.Vector3 tangentFrom,
  required vm.Vector3 tangentTo,
}) {
  final v1 = to - from;
  final c1 = v1.length2;
  if (c1 < 1e-18) return normal;

  final nL = normal - v1 * (2 / c1 * v1.dot(normal));
  final tL = tangentFrom - v1 * (2 / c1 * v1.dot(tangentFrom));

  final v2 = tangentTo - tL;
  final c2 = v2.length2;
  if (c2 < 1e-18) return nL.normalized();

  final nNext = nL - v2 * (2 / c2 * v2.dot(nL));

  // Re-orthogonalise against the new tangent so accumulated error cannot make
  // the frame drift off the normal plane over a long spine.
  final corrected = nNext - tangentTo * tangentTo.dot(nNext);
  return corrected.length2 < 1e-18 ? nL.normalized() : corrected.normalized();
}

/// Builds the meshes for a whole tree: trunk, every limb, and every crown twig.
///
/// Returned in back-to-front order by the engine's own `depth`, so a renderer
/// that cannot depth-sort still draws them plausibly.
List<TubeMesh> buildTreeMeshes(
  ProceduralTree tree, {
  int radialSegments = 12,
  double pixelsPerMetre = kPixelsPerMetre,
}) {
  final out = <({double depth, TubeMesh mesh})>[];

  out.add((
    depth: 0.5,
    mesh: buildTaperedTube(
      spine: stemSpineToScene(tree.trunk, tree.canvas,
          depth: 0.5, pixelsPerMetre: pixelsPerMetre),
      radii: stemRadii(tree.trunk, pixelsPerMetre: pixelsPerMetre),
      radialSegments: radialSegments,
    ),
  ));

  for (final limb in tree.limbs) {
    out.add((
      depth: limb.depth,
      mesh: buildTaperedTube(
        spine: stemSpineToScene(limb.stem, tree.canvas,
            depth: limb.depth, pixelsPerMetre: pixelsPerMetre),
        radii: stemRadii(limb.stem, pixelsPerMetre: pixelsPerMetre),
        radialSegments: radialSegments,
      ),
    ));
  }

  for (final twig in tree.crown) {
    out.add((
      depth: 0.5,
      mesh: buildTaperedTube(
        spine: stemSpineToScene(twig, tree.canvas,
            depth: 0.5, pixelsPerMetre: pixelsPerMetre),
        radii: stemRadii(twig, pixelsPerMetre: pixelsPerMetre),
        radialSegments: math.max(3, radialSegments ~/ 2),
      ),
    ));
  }

  out.sort((a, b) => a.depth.compareTo(b.depth));
  return [for (final e in out) e.mesh];
}
