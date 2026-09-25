// SPIKE -- not production. Delete or promote after the 3D decision is made.
//
// This exists to answer the three questions the flutter_scene gate asks, on a
// real device, rather than by reading a README:
//
//   5. Does Flutter GPU render anything at all here? (the cube)
//   6. Can a real `TreeStem` from `procedural_tree.dart` become a branch mesh?
//   7. Can a real `GameNode` -- cover art, harvest glow, semantics -- live IN
//      the scene and still be tappable and announced?
//
// Question 6 is asked TWICE on purpose. `TubeGeometry` takes a single scalar
// `radius`, but a `TreeStem` carries `halfWidth` PER SPINE SAMPLE, and the
// taper is not cosmetic: the painter's own notes record that a linear taper
// read as a cone and "a cone is why it read as a chess pawn". So a
// constant-radius tube rendering successfully would be a FALSE PASS for the
// port. `_taperedTube` below builds the same stem with its real per-sample
// widths through `GeometryBuilder`, which is the honest test of whether the
// engine can carry Ludeck's tree.

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../../data/enums.dart';
import '../../../data/models.dart';
import '../../map/game_node.dart';
import '../../tokens.dart';
import '../procedural_tree.dart';
import '../tree_mesh.dart';

/// A trunk from the real engine, so the spike is not measuring a hand-made curve.
ProceduralTree _realTree() => ProceduralTree.build(
      canvas: const Size(412, 760),
      branches: const [],
      placements: const {},
      items: [
        TreeItem(
          game: const Game(igdbId: 1, title: 'Astro Bot'),
          entry: const Entry(
            igdbId: 1,
            ownership: Ownership.owned,
            progress: Progress.finished,
          ),
          copies: const [],
        ),
      ],
      fruitRadius: 28,
      trunkWidth: 26,
    );

// Coordinate mapping (canvas pixels, y down -> scene metres, y up) lives in
// `tree_mesh.dart` as `canvasToScene`, and is tested there.

/// A tube that actually tapers.
///
/// The mesh arithmetic now lives in `tree_mesh.dart`, which is pure and unit
/// tested (`test/tree_mesh_test.dart`, 22 invariants including that the
/// per-sample radius survives into vertex positions and that a stem turning
/// toward the camera does not leak NaN). This function is only the GPU-facing
/// adapter: it is the single place that touches `GeometryBuilder`, which is why
/// the arithmetic could be tested on a machine with no GPU.
Geometry _toGeometry(TubeMesh mesh) {
  final b = GeometryBuilder();
  for (var i = 0; i < mesh.vertexCount; i++) {
    // normal/texCoord are STICKY: they apply to every addVertex that follows
    // until changed, so they are set before the position rather than passed
    // alongside it.
    b
      ..normal(mesh.normals[i])
      ..texCoord(mesh.uvs[i])
      ..addVertex(mesh.positions[i]);
  }
  for (var t = 0; t < mesh.indices.length; t += 3) {
    b.addTriangle(mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2]);
  }
  return b.build();
}


class SceneSpikeScreen extends StatefulWidget {
  const SceneSpikeScreen({super.key});

  @override
  State<SceneSpikeScreen> createState() => _SceneSpikeScreenState();
}

class _SceneSpikeScreenState extends State<SceneSpikeScreen> {
  final Scene scene = Scene();
  bool ready = false;
  String status = 'initializing Flutter GPU...';
  int taps = 0;

  @override
  void initState() {
    super.initState();
    // Geometry and materials touch the shader bundle, so nothing may be built
    // before static resources are up. Until then the engine logs "Flutter Scene
    // is not ready to render. Skipping frame."
    Scene.initializeStaticResources().then((_) {
      try {
        _build();
        if (mounted) {
          setState(() {
            ready = true;
            status = 'scene built';
          });
        }
      } catch (e) {
        if (mounted) setState(() => status = 'BUILD FAILED: $e');
      }
    }).catchError((Object e) {
      if (mounted) setState(() => status = 'INIT FAILED: $e');
    });
  }

  void _build() {
    final tree = _realTree();
    final stem = tree.trunk;

    final spine = stemSpineToScene(stem, tree.canvas);
    final radii = stemRadii(stem);

    // Step 5 -- does anything render at all.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.6, 0.6, 0.6)),
          PhysicallyBasedMaterial(),
        ),
      )..position = vm.Vector3(0, 0.7, -2.2),
    );

    // Step 6a -- the engine's own spine as a TubeGeometry. Constant radius, so
    // this proves the path maps and nothing more.
    scene.add(
      Node(
        mesh: Mesh(
          TubeGeometry(PolylinePath(spine), radius: 0.12, stations: 48),
          PhysicallyBasedMaterial(),
        ),
      )..position = vm.Vector3(-0.8, 0, 0),
    );

    // Step 6b -- the SAME stem with its real per-sample taper, which
    // TubeGeometry cannot express. Built through the tested mesh module.
    scene.add(
      Node(
        mesh: Mesh(
          _toGeometry(buildTaperedTube(spine: spine, radii: radii)),
          PhysicallyBasedMaterial(),
        ),
      )..position = vm.Vector3(0.9, 0, 0),
    );

    // Step 7 -- a real GameNode living in the scene: cover art, harvest glow,
    // its own Semantics, and a tap that has to come back through the 3D layer.
    final item = TreeItem(
      game: const Game(igdbId: 1, title: 'Astro Bot'),
      entry: const Entry(
        igdbId: 1,
        ownership: Ownership.owned,
        progress: Progress.finished,
      ),
      copies: const [],
    );

    // Centred and pulled toward the camera. This screen is 1080x2400, so the
    // horizontal span a perspective camera shows at this distance is narrow --
    // a node at x=2.3 rendered entirely off-frame, which reads as "the widget
    // did not render" rather than "the widget is off to the side".
    //
    // NOT rotated: with the camera at -z (see the truth table below) the quad's
    // front face is already toward the camera. Rotating it here as well turns it
    // away and it disappears without a word.
    final widgetNode = Node()..position = vm.Vector3(0, 3.0, -2.2);
    widgetNode.addComponent(
      WidgetComponent(
        size: const Size(96, 128),
        worldHeight: 1.2,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Tokens.cosmos.deep.first.withAlpha(0),
            body: GameNode(
              item: item,
              cardWidth: 96,
              onTap: () {
                if (mounted) setState(() => taps++);
              },
            ),
          ),
        ),
      ),
    );
    scene.add(widgetNode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.cosmos.deep.first,
      body: Stack(
        children: [
          if (ready)
            SceneView(
              scene,
              // NEGATIVE z. Verified on a 1080x2400 device across four builds;
              // the truth table is worth writing down because NOTHING logs when
              // any of it is wrong -- geometry silently mirrors or vanishes.
              //
              //   camera   widget node   widget seen?   world x
              //   -z       none          yes           correct (x=+0.9 renders right)
              //   +z       none          NO            mirrored
              //   +z       rotY 180      yes           mirrored
              //   -z       rotY 180      NO            correct
              //
              // Two independent facts fall out of that:
              //   1. the camera belongs at NEGATIVE z for world x to land on
              //      screen the way the engine's canvas x does;
              //   2. a WidgetComponent's quad is SINGLE-SIDED -- visibility
              //      flips with (camera side XOR node rotation).
              //
              // STILL OPEN: in BOTH visible rows the widget's own texture reads
              // mirrored, so the reversal is intrinsic to how the component maps
              // its texture and is not fixed by facing. Next step is a -1 x scale
              // on the widget node, or whichever flip the component exposes --
              // NOT another camera-sign experiment, which is the wrong axis and
              // cost two builds here.
              //
              // Also verified: the tap in row four registered even though the
              // widget was INVISIBLE, so pointer raycasting is independent of
              // back-face culling. Do not read a working tap as proof the widget
              // is on screen.
              camera: PerspectiveCamera(
                position: vm.Vector3(0, 3.4, -9.5),
                target: vm.Vector3(0, 2.6, 0),
              ),
            ),
          Positioned(
            left: 12,
            top: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'scene spike: $status',
                  style: TextStyle(color: Tokens.palette.text, fontSize: 13),
                ),
                Text(
                  'cover taps: $taps',
                  style: TextStyle(color: Tokens.palette.text, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
