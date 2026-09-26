// The tree as a real 3D scene, orbitable.
//
// This is the promotion of `spike/scene_spike.dart` into production. The spike
// answered the gate's questions on a device (Flutter GPU renders; a tapered
// `TreeStem` becomes a mesh; a real `GameNode` lives in the scene, tappable and
// announced). This wires that into a gesture-driven scene the app can show
// BEHIND A FLAG, with the 2D `ProceduralTreeView` as the default fallback.
//
// WHY BEHIND A FLAG, and what this does NOT do yet.
//
// The 2D painter carries the whole colour system built in Stages 1-3: the
// biolume skin, leaf shapes, the light model and the per-game bloom. None of
// that is ported here -- this scene renders the BARK MESH (coloured by the
// skin's bark values through `UnlitMaterial`) plus the covers as billboarded
// widgets. Foliage, the crown glow and the bloom are a separate materials port,
// so until that lands the 2D tree is the better-looking one and stays the
// default. What this proves is that rotation works end to end on a real
// perspective camera with upright, tappable covers -- which is the thing the
// user asked for and the thing the old "no rotation" rule blocked.
//
// The mesh arithmetic and the coordinate mapping are the PURE, unit-tested
// `tree_mesh.dart`; this file is the GPU-facing shell around it, the one place
// that touches flutter_scene, exactly as the spike established.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../data/models.dart';
import '../map/game_node.dart';
import '../tokens.dart';
import 'procedural_tree.dart';
import 'tree_mesh.dart';

/// Feature flag. The 3D scene is opt-in; the 2D painter ships by default until
/// the colour/foliage materials port lands. Flip to true (or wire to a setting)
/// to preview the orbitable tree.
const bool kTree3DEnabled = false;

/// A GeometryBuilder adapter for one tube mesh. The single place that touches
/// `GeometryBuilder`, kept out of the pure mesh module so that stays GPU-free.
Geometry _toGeometry(TubeMesh mesh) {
  final b = GeometryBuilder();
  for (var i = 0; i < mesh.vertexCount; i++) {
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

vm.Vector4 _toV4(Color c) =>
    vm.Vector4(c.r, c.g, c.b, c.a);

/// A rotatable 3D tree. Data in, orbit gesture, tappable upright covers.
class TreeScene3D extends StatefulWidget {
  const TreeScene3D({
    super.key,
    required this.items,
    this.branches = const [],
    this.placements = const {},
    this.onSelect,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;
  final ValueChanged<TreeItem>? onSelect;

  @override
  State<TreeScene3D> createState() => _TreeScene3DState();
}

class _TreeScene3DState extends State<TreeScene3D>
    with SingleTickerProviderStateMixin {
  final Scene _scene = Scene();
  bool _ready = false;
  String? _error;

  /// Orbit angle about the vertical axis, radians. 0 faces the tree head-on.
  double _yaw = 0;

  /// Distance from the tree, in scene metres. Pinch changes it.
  double _distance = 9.5;

  /// Vertical look target, metres. Vertical drag pans it within bounds.
  double _targetY = 2.6;

  // Gesture scratch: the values at gesture start, so a drag is 1:1 from there.
  double _yaw0 = 0, _dist0 = 9.5, _targetY0 = 2.6;
  Offset? _dragStart;

  /// Active pointers by id, for telling a one-finger orbit from a two-finger
  /// pinch without a GestureDetector (which loses the arena to SceneView).
  final Map<int, Offset> _pointers = {};

  /// The two-finger span at pinch start, or null.
  double? _pinchStart;

  late final AnimationController _spring;

  /// Yaw bounds before the spring pulls back. The tree has a front (covers face
  /// out), so a full spin shows their backs; the orbit is bounded to a
  /// three-quarter turn each way and rubber-banded past it.
  static const double _yawLimit = 2.4;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpring);
    Scene.initializeStaticResources().then((_) {
      try {
        _build();
        _applyBillboards();
        if (mounted) setState(() => _ready = true);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _build() {
    final tree = ProceduralTree.build(
      canvas: const Size(412, 760),
      branches: widget.branches,
      placements: widget.placements,
      items: widget.items,
      fruitRadius: 28,
      trunkWidth: 26,
    );

    // Bark mesh, coloured by the active skin so the 3D tree at least matches the
    // 2D one's wood. Unlit so it needs no light rig to be visible; the skin's
    // three bark values are averaged toward barkMid for a single flat factor
    // (proper per-face shading is the materials port, not this stage).
    final bark = _toV4(Tokens.canopy.barkMid);
    for (final mesh in buildTreeMeshes(tree)) {
      _scene.add(
        Node(
          mesh: Mesh(
            _toGeometry(mesh),
            UnlitMaterial()..baseColorFactor = bark,
          ),
        ),
      );
    }

    // Covers as billboarded widgets. Each fruit is a real GameNode -- cover art,
    // harvest glow, semantics, tap -- exactly as on the 2D tree. Billboarding
    // (facing the camera every frame) is what answers the old objection to
    // rotation: the wood turns, the title never tilts.
    for (final f in tree.allFruit) {
      final worldXY = canvasToScene(f.centre, tree.canvas);
      final z = (f.depth - 0.5) * 2 * 60 / kPixelsPerMetre;
      final node = Node()
        ..position = vm.Vector3(worldXY.x, worldXY.y, z);
      final side = f.radius * 2;
      node.addComponent(
        WidgetComponent(
          size: Size(side, side * Tokens.size.coverRatio),
          worldHeight: (f.radius * 2 / kPixelsPerMetre) * Tokens.size.coverRatio,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Tokens.palette.bg.withValues(alpha: 0),
              body: GameNode(
                item: f.item,
                cardWidth: side,
                showTitle: false,
                onTap: () => widget.onSelect?.call(f.item),
              ),
            ),
          ),
        ),
      );
      _billboards.add(node);
      _scene.add(node);
    }
  }

  final List<Node> _billboards = [];

  void _applyBillboards() {
    // Face each cover at the camera. The camera orbits to world azimuth _yaw
    // (its position is (sin _yaw, _, -cos _yaw) * dist), so a cover facing it
    // must yaw by the SAME angle -- the earlier -_yaw turned covers edge-on at
    // yaw 0.72 on device. Composed with a -1 x scale that fixes the mirrored
    // WidgetComponent texture the spike left open (intrinsic to the quad's
    // texture mapping, so it belongs on every cover, not on the camera).
    final flip = vm.Matrix4.identity()..setEntry(0, 0, -1);
    for (final n in _billboards) {
      n.localTransform = vm.Matrix4.rotationY(-_yaw) * flip;
    }
  }

  void _onSpring() {
    setState(() {
      _yaw = _spring.value;
      _applyBillboards();
    });
  }

  vm.Vector3 _cameraPosition() {
    // Orbit on a circle of radius _distance about the target, at a fixed height.
    final x = math.sin(_yaw) * _distance;
    final zBase = -math.cos(_yaw) * _distance; // -z faces the tree (spike truth table)
    return vm.Vector3(x, 3.4, zBase);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text('3D scene failed: $_error',
            style: TextStyle(color: Tokens.palette.danger)),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      // Raw pointer, NOT a GestureDetector: SceneView does its own pointer
      // hit-testing for WidgetComponent taps and WINS the gesture arena, so a
      // GestureDetector's pan never fired -- the orbit rendered an identical
      // frame until this became a Listener, which cannot be lost to the arena.
      onPointerDown: (e) {
        _spring.stop();
        _pointers[e.pointer] = e.position;
        _yaw0 = _yaw;
        _dist0 = _distance;
        _targetY0 = _targetY;
        _dragStart = e.position;
        _pinchStart = _pinchSpan();
      },
      onPointerMove: (e) {
        _pointers[e.pointer] = e.position;
        setState(() {
          if (_pointers.length >= 2 && _pinchStart != null && _pinchStart! > 0) {
            // Two fingers -> pinch zoom, clamped to a metre range. Closer than
            // 4m clips into the trunk; further than 16m loses the tree.
            final span = _pinchSpan();
            if (span > 0) {
              _distance = (_dist0 * (_pinchStart! / span)).clamp(4.0, 16.0);
            }
          } else if (_dragStart != null) {
            // One finger -> orbit (horizontal) and pan the look target
            // (vertical), each 1:1 from the drag start.
            final dx = e.position.dx - _dragStart!.dx;
            final dy = e.position.dy - _dragStart!.dy;
            _yaw = _yaw0 - dx * 0.005;
            if (_yaw.abs() > _yawLimit) {
              final over = _yaw.abs() - _yawLimit;
              _yaw = _yaw.sign * (_yawLimit + over * Tokens.motion.rubberBand);
            }
            _targetY = (_targetY0 + dy * 0.01).clamp(1.0, 5.0);
          }
          _applyBillboards();
        });
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        // Release past the yaw limit springs back to it, so the orbit never
        // feels like it hit a wall.
        if (_pointers.isEmpty && _yaw.abs() > _yawLimit) {
          _spring.value = _yaw;
          _spring.animateTo(
            _yaw.sign * _yawLimit,
            duration: Tokens.motion.harvest,
            curve: Tokens.motion.easeOut,
          );
        }
      },
      onPointerCancel: (e) => _pointers.remove(e.pointer),
      child: SceneView(
        _scene,
        // cameraBuilder, NOT a fixed `camera`: flutter_scene owns the frame
        // ticker and only re-reads the camera through this builder each frame.
        // A fresh `camera` per build does NOT move the view.
        cameraBuilder: (_) => PerspectiveCamera(
          position: _cameraPosition(),
          target: vm.Vector3(0, _targetY, 0),
        ),
      ),
    );
  }

  /// Distance between the first two active pointers, for pinch.
  double _pinchSpan() {
    if (_pointers.length < 2) return 0;
    final ps = _pointers.values.toList();
    return (ps[0] - ps[1]).distance;
  }
}
