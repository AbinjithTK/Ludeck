import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
// Prefixed: rive_native exports its own Animation and PaintingStyle, which
// collide with Flutter's. This is not optional.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';
import '../tokens.dart';
import 'tree_anchors.dart';
import 'tree_layout.dart' show projectMomentum;

/// The tree, as five parallaxing depth layers with fruit interleaved between
/// them.
///
/// WHAT MAKES THIS READ AS 3D
///
/// Nothing here is 3D. There is no geometry, no camera and no projection. The
/// depth comes from one honest trick: when you drag sideways, each layer moves
/// by a DIFFERENT amount, and two of them move the opposite way. That is
/// parallax, and it is the same cue your eyes use on a real scene, so the brain
/// accepts it without being told to.
///
/// The five factors in [kTreeLayers] are the whole effect. The trunk is the pivot at
/// 0.0 and does not translate at all; the front branches follow your finger at
/// 1.0; the back branches counter-move at -0.85. The ground barely moves at
/// 0.10, because the ground is what the eye trusts as fixed, and a floor that
/// slides destroys the illusion faster than anything else here.
///
/// The trunk does one extra thing: it narrows very slightly as you rotate away
/// from rest. That is foreshortening, and it is the single most convincing cue
/// in the file for the price of one multiplication.
///
/// On release it springs back to rest rather than staying rotated. Held at an
/// extreme the layers separate visibly and the fake shows, and nothing new is
/// revealed by staying there, so the gesture is a tactile nudge rather than a
/// navigation control. That is a deliberate limit of the approach, not an
/// oversight.
class TreeScene extends StatefulWidget {
  const TreeScene({
    super.key,
    required this.items,
    this.onSelect,
    this.onHold,
  });

  final List<TreeItem> items;
  final void Function(TreeItem item)? onSelect;
  final void Function(TreeItem item)? onHold;

  @override
  State<TreeScene> createState() => _TreeSceneState();
}

/// One depth layer: an artboard name and how much it moves.
///
/// `parallax` is a multiplier on the rotation, in artboard units. Negative moves
/// against the finger, which is what far things do.
class TreeLayerSpec {
  const TreeLayerSpec(this.artboard, this.parallax);
  final String artboard;
  final double parallax;
}

/// Back to front. This is also the paint order.
///
/// These five numbers ARE the 3D effect. Nothing else in this file matters as
/// much. The trunk is the pivot and does not translate; the front branches
/// follow the finger; the back branches counter-move; the ground barely moves,
/// because a floor that slides destroys the illusion faster than anything else.
const List<TreeLayerSpec> kTreeLayers = [
  TreeLayerSpec('TreeGround', 0.10),
  TreeLayerSpec('TreeBack', -0.85),
  TreeLayerSpec('TreeMid', -0.35),
  TreeLayerSpec('TreeTrunk', 0.00),
  TreeLayerSpec('TreeFront', 1.00),
];

/// How far the most-parallaxed layer travels, in artboard units, at full
/// rotation. Tuned by eye: below about 30 the effect is invisible, above about
/// 60 the layers visibly come apart.
const double kMaxParallaxShift = 46;

/// Horizontal offset of one layer, in logical pixels.
///
/// Pure arithmetic on purpose, so the effect can be tested without a device.
/// Capturing a mid-drag screenshot turned out not to be possible on this
/// machine, and the numbers are the part worth protecting anyway.
double parallaxOffsetFor(String artboard, double rotation, double scale) {
  final layer = kTreeLayers.firstWhere((l) => l.artboard == artboard);
  return rotation * kMaxParallaxShift * layer.parallax * scale;
}

/// Horizontal squeeze applied to the trunk only.
///
/// A cylinder turning away gets narrower. One multiplication, and it does more
/// for the illusion than the translations do.
double trunkSqueezeFor(double rotation) =>
    1 - (rotation.abs() * 0.06).clamp(0.0, 0.06);

/// Which layer a branch belongs to. Derived from the branch NAME rather than
/// from the anchor's depth value, because a name cannot drift out of sync with
/// the RML and a number can.
String layerForBranch(String branch) {
  if (branch.contains('Front')) return 'TreeFront';
  if (branch.contains('Back')) return 'TreeBack';
  return 'TreeMid'; // mid branches and the leader
}

class _TreeSceneState extends State<TreeScene>
    with SingleTickerProviderStateMixin {
  /// One loader PER LAYER, plus one for the fruit.
  ///
  /// A single shared loader across five concurrent RiveWidgetBuilders fails:
  /// every layer reported RiveFailed. The loader is not safe to fan out, so each
  /// layer gets its own. The asset is 2.5 KB, so five loads cost nothing worth
  /// counting, and this is still one loader per widget rather than one per fruit.
  final Map<String, rv.FileLoader> _treeLoaders = {};
  late final rv.FileLoader _fruitLoader;

  late final AnimationController _spring;

  /// Rest is 0. Clamped to roughly plus or minus one, rubber-banded past that.
  double _rotation = 0;

  @override
  void initState() {
    super.initState();
    for (final layer in kTreeLayers) {
      _treeLoaders[layer.artboard] = rv.FileLoader.fromAsset(
        'assets/tree.riv',
        riveFactory: rv.Factory.rive,
      );
    }
    _fruitLoader = rv.FileLoader.fromAsset(
      'assets/fruit.riv',
      riveFactory: rv.Factory.rive,
    );
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _rotation = _spring.value));
  }

  @override
  void dispose() {
    _spring.dispose();
    for (final l in _treeLoaders.values) {
      l.dispose();
    }
    _fruitLoader.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) => _spring.stop();

  void _onDragUpdate(DragUpdateDetails d, double scale) {
    // 180 logical pixels of drag is one unit of rotation. Past one unit the
    // response is damped rather than clamped, so the gesture never feels like it
    // hit a wall.
    final raw = _rotation + (d.delta.dx / (180 * scale));
    setState(() {
      if (raw.abs() <= 1) {
        _rotation = raw;
      } else {
        final over = raw.abs() - 1;
        _rotation = raw.sign * (1 + over / (1 + over * 3));
      }
    });
  }

  void _onDragEnd(DragEndDetails d, double scale) {
    // Release hands the real velocity to the spring rather than starting from
    // zero, which is what makes a flick feel like it continued rather than being
    // caught.
    //
    // It settles where the momentum carries it, clamped to the limits, rather
    // than springing back to centre. Holding the rotation makes this a real
    // orbit you can leave somewhere, which is what Tolan does with its camera.
    // Returning to centre was the earlier behaviour and it made the gesture a
    // flourish you could not use.
    final v = d.velocity.pixelsPerSecond.dx / (180 * scale);
    final target = (_rotation + projectMomentum(v, Tokens.motion.deceleration))
        .clamp(-1.0, 1.0);

    _spring.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: Tokens.motion.stiffnessDefault,
          ratio: Tokens.motion.dampingDefault,
        ),
        _rotation,
        target,
        v,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit the artboard into the space, preserving aspect. Everything below
        // is authored in artboard units and multiplied by this.
        final scale = math.min(
          constraints.maxWidth / kTreeArtboardSize.width,
          constraints.maxHeight / kTreeArtboardSize.height,
        );
        final w = kTreeArtboardSize.width * scale;
        final h = kTreeArtboardSize.height * scale;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, scale),
          onHorizontalDragEnd: (d) => _onDragEnd(d, scale),
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final layer in kTreeLayers) ...[
                    _buildLayer(layer, scale, w, h),
                    // Fruit sit immediately in front of the layer they hang on,
                    // so the trunk can occlude a fruit on a mid branch. That
                    // occlusion is a depth cue and losing it flattens the scene.
                    ..._buildFruitFor(layer.artboard, scale),
                  ],
                  ..._buildSeeds(scale),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayer(TreeLayerSpec layer, double scale, double w, double h) {
    final dx = parallaxOffsetFor(layer.artboard, _rotation, scale);
    final squeeze =
        layer.artboard == 'TreeTrunk' ? trunkSqueezeFor(_rotation) : 1.0;

    return Positioned(
      left: 0,
      top: 0,
      width: w,
      height: h,
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(dx, 0, 0, 1)
          ..scaleByDouble(squeeze, 1, 1, 1),
        alignment: Alignment.center,
        child: rv.RiveWidgetBuilder(
          fileLoader: _treeLoaders[layer.artboard]!,
          artboardSelector: rv.ArtboardSelector.byName(layer.artboard),
          onFailed: (e, s) =>
              debugPrint('Rive layer ${layer.artboard} failed: $e'),
          builder: (context, state) => switch (state) {
            rv.RiveLoaded() => rv.RiveWidget(
                controller: state.controller,
                fit: rv.Fit.contain,
              ),
            // A failed or loading layer renders nothing. Losing one layer should
            // degrade the tree, not replace it with a diagnostic.
            //
            // This silence cost an hour once: all five layers were failing with
            // "Artboard not found" and the empty fallback hid it. The onFailed
            // callback above is what makes the silence survivable, so do not
            // remove it.
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  /// Fruit hanging on the branches of one layer.
  ///
  /// Items are assigned to anchors in order. Anchors outnumber a small
  /// collection, so early games take the front branches, which is where they
  /// read best.
  List<Widget> _buildFruitFor(String artboard, double scale) {
    final hanging = widget.items.where((i) => !i.isSeed).toList();
    if (hanging.isEmpty) return const [];

    final out = <Widget>[];
    for (var i = 0; i < kBranchAnchors.length && i < hanging.length; i++) {
      final anchor = kBranchAnchors[i];
      if (layerForBranch(anchor.branch) != artboard) continue;

      final dx = parallaxOffsetFor(artboard, _rotation, scale);
      final r = fruitRadiusForDepth(anchor.depth) * scale;
      final item = hanging[i];

      out.add(Positioned(
        left: (anchor.position.dx * scale) - r + dx,
        // Hung, not centred. A fruit centred on the branch line looks threaded
        // through it; dropping it most of a radius puts the branch across its
        // top, which is where a stem would attach. The Rive artboard's stem
        // protrudes upward and reinforces this.
        top: (anchor.position.dy * scale) - (r * 0.3),
        width: r * 2,
        height: r * 2,
        child: _Fruit(
          item: item,
          radius: r,
          depth: anchor.depth,
          fruitLoader: _fruitLoader,
          onTap: () => widget.onSelect?.call(item),
          onHold: () => widget.onHold?.call(item),
        ),
      ));
    }
    return out;
  }

  /// Seeds rest in the soil. They are spotted, not owned, so they are not on a
  /// branch at all and they may rest there forever without reproach.
  List<Widget> _buildSeeds(double scale) {
    final seeds = widget.items.where((i) => i.isSeed).toList();
    final out = <Widget>[];
    for (var i = 0; i < seeds.length && i < kSoilAnchors.length; i++) {
      final p = kSoilAnchors[i];
      const r = 7.0;
      out.add(Positioned(
        left: (p.dx * scale) - (r * scale),
        top: (p.dy * scale) - (r * scale),
        width: r * 2 * scale,
        height: r * 2 * scale,
        child: GestureDetector(
          onTap: () => widget.onSelect?.call(seeds[i]),
          onLongPress: () => widget.onHold?.call(seeds[i]),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Tokens.palette.textDim.withValues(alpha: 0.55),
            ),
          ),
        ),
      ));
    }
    return out;
  }
}

/// One fruit.
///
/// Harvested fruit are the authored Rive artboard: gold, with the volume and the
/// highlight that make a circle read as a sphere. Everything else is painted.
///
/// That split is deliberate and it is not a shortcut. The Rive artboard has one
/// hardcoded gold, and colour is what carries status here, so tinting it would
/// trade meaning for polish. Making the good-looking fruit the HARVESTED one means
/// the thing the app is pointing at is the thing that looks best, which is what
/// you want anyway.
class _Fruit extends StatefulWidget {
  const _Fruit({
    required this.item,
    required this.radius,
    required this.depth,
    required this.fruitLoader,
    required this.onTap,
    required this.onHold,
  });

  final TreeItem item;
  final double radius;
  final double depth;
  final rv.FileLoader fruitLoader;
  final VoidCallback onTap;
  final VoidCallback onHold;

  @override
  State<_Fruit> createState() => _FruitState();
}

class _FruitState extends State<_Fruit> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    // Distance reads as loss of contrast. A fruit on a back branch is both
    // smaller, which the radius already handles, and dimmer.
    final opacity = 0.55 + (widget.depth * 0.45);

    return GestureDetector(
      // On pointer-down, not on tap-up. A press that waits for release feels
      // broken even when the timing is identical.
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onHold,
      child: AnimatedScale(
        scale: _pressed ? Tokens.motion.pressScale : 1.0,
        duration: Tokens.motion.press,
        curve: Tokens.motion.easeOut,
        child: Opacity(
          opacity: opacity,
          child: _ringed(
            item.isHarvested
                ? rv.RiveWidgetBuilder(
                    fileLoader: widget.fruitLoader,
                    builder: (context, state) => switch (state) {
                      // The artboard is 240x240 and the fruit BODY is 112 across,
                      // so Fit.contain renders the body at only 47% of the box and
                      // a harvested fruit came out visibly smaller than a painted one.
                      // Scaling by 240/112 makes the body fill the box, so both
                      // kinds of fruit are the same apparent size. The stem and
                      // halo overflow the box, which is wanted: the stem is what
                      // makes it read as hung.
                      rv.RiveLoaded() => Transform.scale(
                          scale: 240 / 112,
                          child: rv.RiveWidget(
                            controller: state.controller,
                            fit: rv.Fit.contain,
                          ),
                        ),
                      _ => _PaintedFruit(item: item),
                    },
                  )
                : _PaintedFruit(item: item),
          ),
        ),
      ),
    );
  }

  /// Wraps a harvested fruit in a ring.
  ///
  /// This exists for a specific accessibility failure found in a design
  /// critique: completion was carried by COLOUR ALONE. Every fruit was the same
  /// circle at the same size and only the fill differed, so under deuteranopia
  /// the gold and the greys sit at similar lightness and the single most
  /// important status in the app becomes unreadable.
  ///
  /// A ring is a second, non-colour cue for the same fact. It also happens to
  /// suit the metaphor: a harvested fruit has been picked, and a ring reads as
  /// the place it was taken from.
  ///
  /// Everything unharvested is returned untouched, so the ring means exactly one
  /// thing and there is no second state to learn.
  Widget _ringed(Widget child) {
    if (!widget.item.isHarvested) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Tokens.palette.text, width: 1.4),
      ),
      // Insets the fruit so the ring sits clear of the body rather than on its
      // edge, where it would read as a rendering artefact instead of a mark.
      child: Padding(padding: const EdgeInsets.all(2.5), child: child),
    );
  }
}

/// A fruit drawn rather than authored, with a highlight that matches the Rive
/// artboard's placement so the two read as the same object in two states.
class _PaintedFruit extends StatelessWidget {
  const _PaintedFruit({required this.item});

  final TreeItem item;

  /// Harvested is accent so the painted fallback matches the gold Rive artboard,
  /// which is what a harvested fruit normally renders as. Everything else is dim.
  ///
  /// This used to read `if (isHarvested) return text;` followed by an identical
  /// `if (isHarvested) return accent;`. The second line was unreachable: it had
  /// been `isRipe` and a scripted rename rewrote it into a duplicate of the line
  /// above. Valid Dart, so the analyzer said nothing.
  Color get _colour =>
      item.isHarvested ? Tokens.palette.accent : Tokens.palette.textDim;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The highlight sits high and off to one side, which is the whole reason
        // a flat circle reads as a sphere. Same offset as the Rive artboard.
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [
            Color.lerp(_colour, Tokens.palette.text, 0.35)!,
            _colour,
            Color.lerp(_colour, Tokens.palette.bg, 0.30)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}
