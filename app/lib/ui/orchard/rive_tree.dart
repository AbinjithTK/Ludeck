// One Rive tree: the orchard's pages and the Add screen's discovery tree are
// both this widget. It feeds the file's view model (rive/AGENTS.md has the
// contract) and reports what the user did to it.
//
// The .riv is loaded ONCE per app run ([loadTreeFile]) and every tree
// instantiates its own artboard from it. A loader per widget would reparse the
// file per page; a single FileLoader fanned out to several builders failed
// outright on this project before (every layer reported RiveFailed).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';

/// Fruit slots in the file.
const int kTreeSlots = 12;

/// Pixel size the file's cover slots are drawn from.
const int kCoverW = 240, kCoverH = 320;

/// Artboard geometry.
const double kTreeArtW = 412, kTreeArtH = 732;

/// Top of the full-grown canopy in artboard units, less a little headroom.
const double kCanopyTop = 185;

/// The soil line: where the trunk meets the ground, in artboard units
/// (TREE_Y in rive/tree/discovery.py).
const double kTreeBaseY = 668;

/// How close the orchard's camera sits to a tree holding [grown] games.
///
/// A sapling framed at the full tree's scale fills a third of the screen and
/// leaves the rest as empty sky, so a young tree is framed 1.3x closer and the
/// camera eases back as it fills in, reaching 1.0 at 4 games. It never gets
/// closer as games are added, so the tree only ever looks bigger. Fruit pops
/// centre-out, so the few fruit a young tree carries are never the ones the
/// closer framing crops at the edges.
double treeZoom(int grown) {
  final t = (grown / 4).clamp(0.0, 1.0);
  return 1.3 - 0.3 * t;
}

/// Where the artboard goes in a [box] so its soil line sits at [groundY],
/// at camera [zoom]. Fits the width, but never so large that the full tree
/// would reach up into the [headroom] kept for the page's title.
Rect treeFrame(Size box, double groundY, double zoom, {double headroom = 140}) {
  final byWidth = box.width / kTreeArtW;
  final byHeight = (groundY - headroom) / (kTreeBaseY - kCanopyTop);
  final s = (byWidth < byHeight ? byWidth : byHeight).clamp(0.1, 100.0) * zoom;
  final w = kTreeArtW * s, h = kTreeArtH * s;
  return Rect.fromLTWH((box.width - w) / 2, groundY - kTreeBaseY * s, w, h);
}

Future<rv.File?>? _treeFile;

/// The tree file, loaded once. Resolves to null where Rive cannot run (the
/// headless test host has no native library): callers degrade to nothing.
Future<rv.File?> loadTreeFile() => _treeFile ??= () async {
      try {
        return await rv.File.asset('assets/rive/tree_discovery.riv',
            riveFactory: rv.Factory.rive);
      } catch (e) {
        debugPrint('RiveTree: Rive unavailable ($e)');
        return null;
      }
    }();

/// The tree's next size. Never below [current]: the metaphor never shrinks
/// (DECISIONS.md). Capped at the file's slots.
double nextGrown(double current, int target) {
  final want = target.clamp(0, kTreeSlots).toDouble();
  return want > current ? want : current;
}

/// Imperative handle for the few things that are events, not state.
class RiveTreeController {
  _RiveTreeState? _state;

  /// Shake the tree and drop fruit [slot] (the pick). [slot] < 0 hangs it back.
  void drop(int slot) => _state?._setNumber('drop', slot.toDouble());

  /// Which fruit the pointer last went down on, or -1. Read on long-press.
  int get pressed => _state?._readNumber('pressed')?.round() ?? -1;
}

class RiveTree extends StatefulWidget {
  const RiveTree({
    super.key,
    required this.games,
    required this.grownTarget,
    this.planted = true,
    this.onFruitTap,
    this.controller,
    this.alignment,
    this.fit = rv.Fit.cover,
  });

  /// Fruit, in slot order (slot 0 is the canopy centre). Only the first
  /// [kTreeSlots] hang.
  final List<Game> games;

  /// How big the tree should be (0..12). Only ever raised internally.
  final int grownTarget;

  /// False shows the empty patch; flipping to true plays seed -> sapling.
  final bool planted;

  final void Function(int slot)? onFruitTap;
  final RiveTreeController? controller;
  final Alignment? alignment;
  final rv.Fit fit;

  @override
  State<RiveTree> createState() => _RiveTreeState();
}

class _RiveTreeState extends State<RiveTree> {
  rv.RiveWidgetController? _controller;
  rv.ViewModelInstance? _vm;
  rv.ViewModelInstanceNumber? _selected;
  bool _failed = false;
  double _grownTo = 0;

  /// Bumped per fruit set, so a slow cover never lands on a card that now
  /// shows a different game.
  int _generation = 0;
  Timer? _repop;

  List<Game> get _hung => widget.games.take(kTreeSlots).toList();

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _load();
  }

  Future<void> _load() async {
    final file = await loadTreeFile();
    if (!mounted) return;
    if (file == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final c = rv.RiveWidgetController(file,
          artboardSelector: rv.ArtboardSelector.byName('TreeDiscovery'));
      final vm = c.dataBind(rv.DataBind.auto());
      setState(() {
        _controller = c;
        _vm = vm;
      });
      _selected = vm.number('selected');
      _selected?.addListener(_onSelected);
      vm.boolean('planted')?.value = widget.planted;
      _feed();
    } catch (e) {
      debugPrint('RiveTree: artboard failed ($e)');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(RiveTree old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.planted != widget.planted) {
      _vm?.boolean('planted')?.value = widget.planted;
    }
    final before = old.games.take(kTreeSlots).map((g) => g.igdbId).toList();
    final after = _hung.map((g) => g.igdbId).toList();
    if (_sameIds(before, after) && old.grownTarget == widget.grownTarget) return;
    if (_isAppend(before, after)) {
      // New fruit on the end: just hang it. Nothing already there re-pops.
      _feed();
      return;
    }
    // A different set: the cards step aside and the new set pops in fresh.
    // Only the CARDS reset; the tree keeps its size.
    _generation++;
    _setNumber('selected', -1);
    _setNumber('found', 0);
    _repop?.cancel();
    _repop = Timer(const Duration(milliseconds: 260), _feed);
  }

  void _feed() {
    if (!mounted || _vm == null) return;
    final hung = _hung;
    final gen = _generation;
    for (var i = 0; i < hung.length; i++) {
      final url = hung[i].coverUrl;
      if (url != null && url.isNotEmpty) _loadCover(i, url, gen);
    }
    _grownTo = nextGrown(_grownTo, widget.grownTarget);
    _setNumber('grown', _grownTo);
    _setNumber('found', hung.length.toDouble());
  }

  Future<void> _loadCover(int slot, String url, int gen) async {
    try {
      final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final png = await coverFitPng(bytes.buffer.asUint8List());
      final image = await rv.Factory.rive.decodeImage(png);
      if (!mounted || gen != _generation || image == null) return;
      _vm?.image('cover${slot + 1}')?.value = image;
    } catch (_) {
      // Keep the placeholder art; the game is still named everywhere else.
    }
  }

  void _onSelected(double value) {
    final i = value.round();
    if (i < 0) return;
    widget.onFruitTap?.call(i);
    // Back to rest, so the same fruit can be tapped again after the sheet.
    _setNumber('selected', -1);
  }

  void _setNumber(String name, double v) => _vm?.number(name)?.value = v;
  double? _readNumber(String name) => _vm?.number(name)?.value;

  @override
  void dispose() {
    _repop?.cancel();
    if (widget.controller?._state == this) widget.controller?._state = null;
    _selected?.removeListener(_onSelected);
    _controller?.dispose();
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) => rv.RiveWidget(
        controller: c,
        fit: widget.fit,
        alignment: widget.alignment ?? canopyAlignment(box.maxWidth, box.maxHeight),
        hitTestBehavior: rv.RiveHitTestBehavior.translucent,
      ),
    );
  }
}

bool _sameIds(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True when [after] is [before] with games added at the end.
bool _isAppend(List<int> before, List<int> after) {
  if (after.length < before.length) return false;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) return false;
  }
  return true;
}

/// Vertical alignment that puts the grown canopy at the top of a [w]x[h] box
/// when the 412x732 artboard is scaled to cover it.
Alignment canopyAlignment(double w, double h) {
  if (w <= 0 || h <= 0) return Alignment.center;
  final scale = (w / kTreeArtW) > (h / kTreeArtH) ? w / kTreeArtW : h / kTreeArtH;
  final visible = h / scale;
  final overflow = kTreeArtH - visible;
  if (overflow <= 0) return Alignment.center;
  final y = (2 * kCanopyTop / overflow - 1).clamp(-1.0, 1.0);
  return Alignment(0, y);
}

/// Scale-and-crop [bytes] to exactly [kCoverW]x[kCoverH] (BoxFit.cover), as PNG.
Future<Uint8List> coverFitPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final src = (await codec.getNextFrame()).image;
  final sw = src.width.toDouble(), sh = src.height.toDouble();
  final scale = (kCoverW / sw) > (kCoverH / sh) ? kCoverW / sw : kCoverH / sh;
  final cw = kCoverW / scale, ch = kCoverH / scale;
  final from = Rect.fromLTWH((sw - cw) / 2, (sh - ch) / 2, cw, ch);
  final to = Rect.fromLTWH(0, 0, kCoverW.toDouble(), kCoverH.toDouble());
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(src, from, to, Paint()..filterQuality = FilterQuality.medium);
  final out = await rec.endRecording().toImage(kCoverW, kCoverH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  src.dispose();
  out.dispose();
  return data!.buffer.asUint8List();
}
