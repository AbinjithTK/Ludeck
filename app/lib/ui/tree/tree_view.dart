import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
// Prefixed deliberately: rive_native exports its own Animation and
// PaintingStyle, which collide with Flutter's. A prefix is the fix; hiding
// individual names would break again on the next version bump.
import 'package:rive/rive.dart' as rv;

import '../../data/enums.dart';
import '../../data/models.dart';
import '../tokens.dart';
import 'tree_layout.dart';

/// The tree. The main screen.
///
/// Gestures, and why each is shaped this way:
///  - ONE finger: horizontal drag orbits, vertical drag pans. Both track the
///    finger 1:1 the whole way, never only on release.
///  - TWO fingers: pinch zooms about the focal point, and the focal delta pans,
///    because a zoom that ignores where your fingers are feels wrong.
///  - Release: velocity is PROJECTED forward to decide where the orbit lands,
///    then handed to the spring as its initial velocity, so there is no seam
///    between dragging and animating.
///  - Bounds rubber-band rather than hard-stopping. A hard stop reads as frozen.
///
/// The tree does NOT animate on open. It is already grown; it renders at its
/// final state instantly. Growth animates only when something is actually
/// captured, which is the difference between a metaphor and a loading screen.
class TreeView extends StatefulWidget {
  const TreeView({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onHold,
    this.platformFilter,
    required this.onFilterPlatform,
  });

  final List<TreeItem> items;
  final void Function(TreeItem) onSelect;
  final void Function(TreeItem) onHold;
  final Platform? platformFilter;
  final void Function(Platform?) onFilterPlatform;

  @override
  State<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<TreeView>
    with SingleTickerProviderStateMixin {
  double _zoom = 1.0;
  double _orbit = 0.0; // -1 .. 1, normalised
  double _panY = 0.0;

  double _zoomAtGestureStart = 1.0;
  late AnimationController _settle;
  Animation<double>? _orbitAnim;

  TreeItem? _pressed;

  /// ONE loader for the whole tree. Creating a FileLoader per fruit would parse
  /// and hold the same 401-byte file once per game on screen.
  late final rv.FileLoader _fruitLoader = rv.FileLoader.fromAsset(
    'assets/fruit.riv',
    riveFactory: rv.Factory.rive,
  );

  @override
  void initState() {
    super.initState();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (_orbitAnim != null) {
          setState(() => _orbit = _orbitAnim!.value.clamp(-1.0, 1.0));
        }
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _onScaleStart(ScaleStartDetails d) {
    _settle.stop();
    _zoomAtGestureStart = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size canvas) {
    setState(() {
      if (d.pointerCount >= 2) {
        final raw = _zoomAtGestureStart * d.scale;
        _zoom = _clampWithRubberBand(
          raw,
          Tokens.motion.zoomMin,
          Tokens.motion.zoomMax,
        );
        _panY += d.focalPointDelta.dy;
      } else {
        // Horizontal orbits, vertical pans. Normalised by width so the same
        // finger travel rotates the same amount on any screen.
        if (!_reduceMotion) {
          _orbit = (_orbit + d.focalPointDelta.dx / canvas.width)
              .clamp(-1.0, 1.0);
        }
        _panY += d.focalPointDelta.dy;
      }
      _panY = _panY.clamp(-canvas.height * 0.4, canvas.height * 0.25);
    });
  }

  void _onScaleEnd(ScaleEndDetails d, Size canvas) {
    if (_reduceMotion) return;

    // Where would the orbit come to rest if released now?
    final vx = d.velocity.pixelsPerSecond.dx;
    if (vx.abs() < 40) return;

    final projected = _orbit +
        projectMomentum(vx, Tokens.motion.deceleration) / canvas.width;
    final target = projected.clamp(-1.0, 1.0);

    // Bounce ONLY because a flick supplied the momentum.
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: Tokens.motion.stiffnessDefault,
      ratio: Tokens.motion.dampingMomentum,
    );

    _orbitAnim = _settle.drive(Tween<double>(begin: _orbit, end: _orbit));
    _settle.value = _orbit;
    _orbitAnim = _settle;
    _settle.animateWith(
      SpringSimulation(spring, _orbit, target, vx / canvas.width),
    );
  }

  double _clampWithRubberBand(double v, double lo, double hi) {
    if (v < lo) {
      return lo -
          rubberBand(lo - v, hi - lo, Tokens.motion.rubberBand);
    }
    if (v > hi) {
      return hi +
          rubberBand(v - hi, hi - lo, Tokens.motion.rubberBand);
    }
    return v;
  }

  Offset _toLayoutSpace(Offset local, Size canvas) {
    // Undo the same transform the painter applies, so a tap lands on the fruit
    // the user actually sees rather than where it would be unzoomed.
    final centre = Offset(canvas.width / 2, canvas.height / 2);
    return (local - centre - Offset(0, _panY)) / _zoom + centre;
  }

  bool _dimmed(FruitGeom f) =>
      widget.platformFilter != null &&
      !f.item.platforms.contains(widget.platformFilter);

  /// The fruit artboard's own geometry, read off rive/fruit/scene.rml. These are
  /// not guesses: the body Shape sits at (120, 140) in a 240x240 artboard with a
  /// 112px diameter, so the body's centre is 0.5 across and 0.583 down.
  static const double _artboardSize = 240;
  static const double _bodyCentreX = 120;
  static const double _bodyCentreY = 140;
  static const double _bodyRadius = 56;

  /// Places the artboard so its BODY centre lands on the layout's fruit centre,
  /// at the layout's radius. Getting this wrong is what makes an overlay drift
  /// away from the thing it is supposed to be replacing.
  Widget _positionedFruit(FruitGeom f) {
    final isPressed =
        _pressed != null && _pressed!.game.igdbId == f.item.game.igdbId;

    // Parallax has to be applied here too, or the Rive layer slides out of
    // register with the painted branches when the tree is orbited.
    final shift = (_reduceMotion ? 0 : _orbit) * 34 * (1 - f.depth);

    final scale = (f.radius / _bodyRadius) *
        (isPressed ? Tokens.motion.pressScale : 1.0);
    final side = _artboardSize * scale;

    return Positioned(
      left: f.centre.dx + shift - _bodyCentreX * scale,
      top: f.centre.dy - _bodyCentreY * scale,
      width: side,
      height: side,
      child: IgnorePointer(
        // The gesture layer owns hit testing against TreeLayout, which is what
        // the accessible list path and the 20 layout tests both rely on. Letting
        // Rive swallow taps would fork that logic in two.
        child: Opacity(
          opacity: 1 - f.depth * 0.3,
          child: rv.RiveWidgetBuilder(
            fileLoader: _fruitLoader,
            builder: (context, state) => switch (state) {
              rv.RiveLoaded() => rv.RiveWidget(
                  controller: state.controller,
                  fit: rv.Fit.contain,
                ),
              // A fruit that has not loaded yet must still occupy its space, or
              // the tree visibly reflows as artboards arrive.
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Size(constraints.maxWidth, constraints.maxHeight);
        final centre = Offset(canvas.width / 2, canvas.height / 2);

        final visible = widget.platformFilter == null
            ? widget.items
            : widget.items
                .where((i) =>
                    i.isSeed || i.platforms.contains(widget.platformFilter))
                .toList();

        final layout = TreeLayout.build(
          canvas: canvas,
          items: visible,
          fruitRadius: Tokens.size.fruit / 2,
          trunkWidth: Tokens.size.trunk,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: (d) => _onScaleUpdate(d, canvas),
          onScaleEnd: (d) => _onScaleEnd(d, canvas),
          onTapDown: (d) {
            // Feedback on pointer DOWN, not on release. Waiting for the tap to
            // complete is the single thing that makes an interface feel dead.
            final hit = layout.hitTest(_toLayoutSpace(d.localPosition, canvas));
            if (hit != null) setState(() => _pressed = hit);
          },
          onTapCancel: () => setState(() => _pressed = null),
          onTap: () {
            final hit = _pressed;
            setState(() => _pressed = null);
            if (hit != null) {
              widget.onSelect(hit);
              return;
            }
          },
          onTapUp: (d) {
            if (_pressed != null) return;
            // Not a fruit. A branch tap filters to that platform; tapping the
            // same branch again clears it. The control IS the thing it affects.
            final p = layout
                .hitTestBranch(_toLayoutSpace(d.localPosition, canvas));
            if (p != null) {
              widget.onFilterPlatform(
                  widget.platformFilter == p ? null : p);
            } else if (widget.platformFilter != null) {
              widget.onFilterPlatform(null);
            }
          },
          onLongPressStart: (d) {
            final hit = layout.hitTest(_toLayoutSpace(d.localPosition, canvas));
            if (hit != null) {
              HapticFeedback.mediumImpact();
              widget.onHold(hit);
            }
          },
          child: Stack(
            children: [
              CustomPaint(
                size: canvas,
                painter: _TreePainter(
                  layout: layout,
                  zoom: _zoom,
                  orbit: _reduceMotion ? 0 : _orbit,
                  panY: _panY,
                  pressed: _pressed,
                  highlight: widget.platformFilter,
                ),
              ),

              // Ripe fruit is drawn by Rive rather than by the painter, because
              // ripe is the state the whole screen exists to answer and a flat
              // circle does not sell it. The other statuses stay painted: the
              // artboard is a single colour, and colour is what carries status,
              // so swapping them all would trade meaning for polish.
              //
              // Positioned in the SAME layout coordinates the painter uses, under
              // the same transform, which is what keeps the two layers in
              // register while zooming and orbiting.
              Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(centre.dx, centre.dy + _panY, 0, 1)
                  ..scaleByDouble(_zoom, _zoom, 1, 1)
                  ..translateByDouble(-centre.dx, -centre.dy, 0, 1),
                child: Stack(
                  children: [
                    for (final b in layout.branches)
                      for (final f in b.fruit)
                        if (f.harvested && !_dimmed(f))
                          _positionedFruit(f),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.layout,
    required this.zoom,
    required this.orbit,
    required this.panY,
    required this.pressed,
    required this.highlight,
  });

  final TreeLayout layout;
  final double zoom;
  final double orbit;
  final double panY;
  final TreeItem? pressed;
  final Platform? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Tokens.palette.bg,
    );

    canvas.save();
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.translate(centre.dx, centre.dy + panY);
    canvas.scale(zoom);
    canvas.translate(-centre.dx, -centre.dy);

    _paintSoil(canvas, size);

    // Furthest branches first, so nearer ones occlude them. This ordering IS
    // the depth illusion; without it the parallax reads as jitter.
    final ordered = [...layout.branches]
      ..sort((a, b) => b.depth.compareTo(a.depth));

    _paintTrunk(canvas);

    for (final b in ordered) {
      _paintBranch(canvas, b);
    }
    for (final b in ordered) {
      for (final f in b.fruit) {
        _paintFruit(canvas, f);
      }
    }
    for (final s in layout.seeds) {
      _paintSeed(canvas, s);
    }

    canvas.restore();
  }

  /// Parallax: a branch further back shifts LESS than one in front, which is
  /// what the eye reads as rotation.
  double _shift(double depth) => orbit * 34 * (1 - depth);

  void _paintSoil(Canvas canvas, Size size) {
    final p = Paint()..color = Tokens.palette.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, layout.soilY, size.width, size.height - layout.soilY),
        Radius.circular(Tokens.radius.card),
      ),
      p,
    );
  }

  void _paintTrunk(Canvas canvas) {
    final dx = _shift(0.15);
    final path = Path()
      ..moveTo(layout.trunkBase.dx - Tokens.size.trunk / 2, layout.trunkBase.dy)
      ..quadraticBezierTo(
        layout.trunkBase.dx - Tokens.size.trunk / 3 + dx,
        (layout.trunkBase.dy + layout.trunkTop.dy) / 2,
        layout.trunkTop.dx - 3 + dx,
        layout.trunkTop.dy,
      )
      ..lineTo(layout.trunkTop.dx + 3 + dx, layout.trunkTop.dy)
      ..quadraticBezierTo(
        layout.trunkBase.dx + Tokens.size.trunk / 3 + dx,
        (layout.trunkBase.dy + layout.trunkTop.dy) / 2,
        layout.trunkBase.dx + Tokens.size.trunk / 2,
        layout.trunkBase.dy,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = Tokens.palette.surface);
  }

  void _paintBranch(Canvas canvas, BranchGeom b) {
    final dim = highlight != null && highlight != b.platform;
    final dx = _shift(b.depth);

    final paint = Paint()
      ..color = Tokens.palette.surface
          .withValues(alpha: dim ? b.opacity * 0.35 : b.opacity)
      ..strokeWidth = b.thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // A slight bow, because a straight line does not read as a branch.
    final mid = Offset.lerp(b.start, b.tip, 0.5)!;
    final bow = Offset(mid.dx + dx, mid.dy - b.thickness * 1.6);

    canvas.drawPath(
      Path()
        ..moveTo(b.start.dx, b.start.dy)
        ..quadraticBezierTo(bow.dx, bow.dy, b.tip.dx + dx, b.tip.dy),
      paint,
    );
  }

  void _paintFruit(Canvas canvas, FruitGeom f) {
    final dim = highlight != null && !f.item.platforms.contains(highlight);
    final isPressed = pressed != null &&
        pressed!.game.igdbId == f.item.game.igdbId;

    final r = f.radius *
        (isPressed ? Tokens.motion.pressScale : 1.0);
    final c = Offset(f.centre.dx + _shift(f.depth), f.centre.dy);

    // Harvested fruit is the brightest thing on the tree, because finishing a
    // game is the achievement the app is built to celebrate. Ripe is accent.
    // Everything else is quiet: a full tree must not shout.
    final Color fill;
    if (f.harvested) {
      fill = Tokens.palette.text;
    } else if (f.harvested) {
      fill = Tokens.palette.accent;
    } else if (f.item.entry.progress == Progress.abandoned) {
      fill = Tokens.palette.danger;
    } else {
      fill = Tokens.palette.textDim;
    }

    final alpha = (dim ? 0.3 : 1.0) * (1 - f.depth * 0.3);

    // A ripe, undimmed fruit is drawn by Rive in the overlay layer, so the
    // painter must NOT draw its body or stem as well: two fruit in the same
    // place is worse than either alone. The halo stays here, because it is a
    // glow the artboard does not carry and it is what makes "playable" findable.
    if (f.harvested && !dim) {
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()..color = Tokens.palette.accent.withValues(alpha: 0.14),
      );
      return;
    }

    // A stem, so fruit reads as attached rather than floating.
    canvas.drawLine(
      Offset(c.dx, c.dy - r * 1.5),
      Offset(c.dx, c.dy - r * 0.6),
      Paint()
        ..color = Tokens.palette.textDim.withValues(alpha: alpha)
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      c,
      r,
      Paint()..color = fill.withValues(alpha: alpha),
    );
  }

  void _paintSeed(Canvas canvas, SeedGeom s) {
    canvas.drawCircle(
      s.centre,
      s.radius,
      Paint()..color = Tokens.palette.textDim.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.zoom != zoom ||
      old.orbit != orbit ||
      old.panY != panY ||
      old.pressed != pressed ||
      old.highlight != highlight ||
      old.layout != layout;
}
