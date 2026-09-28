// One Rive tree: the orchard's pages and the Add screen's discovery tree are
// both this widget. It feeds the file's view model (rive/AGENTS.md has the
// contract) and reports what the user did to it.
//
// The .riv is loaded ONCE per app run ([loadTreeFile]) and every tree
// instantiates its own artboard from it. A loader per widget would reparse the
// file per page; a single FileLoader fanned out to several builders failed
// outright on this project before (every layer reported RiveFailed).

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';
import 'fruit_look.dart';

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

/// The Add screen's tree, and the look every tree had before styles.
const String kDefaultTreeAsset = 'assets/rive/tree_discovery.riv';

final Map<String, Future<rv.File?>> _treeFiles = {};

/// A tree file, loaded once per app run per [asset] (each tree look is its own
/// baked file; see tree_style.dart). Resolves to null where Rive cannot run
/// (the headless test host has no native library): callers degrade to nothing.
Future<rv.File?> loadTreeFile([String asset = kDefaultTreeAsset]) =>
    _treeFiles[asset] ??= () async {
      try {
        return await rv.File.asset(asset, riveFactory: rv.Factory.rive);
      } catch (e) {
        debugPrint('RiveTree: Rive unavailable for $asset ($e)');
        return null;
      }
    }();

/// The tree's next size. Never below [current]: the metaphor never shrinks
/// (DECISIONS.md). Capped at the file's slots.
double nextGrown(double current, int target) {
  final want = target.clamp(0, kTreeSlots).toDouble();
  return want > current ? want : current;
}

/// The tree's next size when it follows what it holds: exactly [target].
///
/// An orchard tree is its games, so it grows as they are hung and eases back
/// when the user moves one off (DECISIONS.md, 2026-09-28: only the user's own
/// action shrinks a tree; nothing ever shrinks it with time or neglect). A
/// shake never removes a game, so a shake never shrinks a tree.
double followGrown(int target) => target.clamp(0, kTreeSlots).toDouble();

/// Growth-curve exponent. MUST equal SHAPE in rive/tree/fit.py: the fruit
/// placement is solved against the canopy at exactly these sizes.
const double kTreeGrowthShape = 1.8;

/// The file's `grown` value for a tree holding [games] games.
///
/// Front-loaded: the first games grow the tree most (a tree holding 3 already
/// has 40% of its size, not 25%), because early on every game should visibly
/// change the tree, and by the tenth the canopy is full and the fruit is the
/// story. Monotonic, so the only-grow rule of [nextGrown] survives it.
double treeSize(double games) {
  final t = (games / kTreeSlots).clamp(0.0, 1.0);
  return kTreeSlots * (1 - math.pow(1 - t, kTreeGrowthShape).toDouble());
}

/// Imperative handle for the few things that are events, not state.
class RiveTreeController {
  _RiveTreeState? _state;

  /// Shake the tree and drop fruit [slot] (the pick). [slot] < 0 hangs it back.
  void drop(int slot) => _state?._setNumber('drop', slot.toDouble());

  /// Which fruit the pointer last went down on, or -1. Read on long-press.
  /// STALE by design of the file: only a press on the sky resets it, so the
  /// host must check the press was really on that fruit ([clearPressed]).
  int get pressed => _state?._readNumber('pressed')?.round() ?? -1;

  /// Forget the last pressed fruit, once a long-press has used (or refused) it.
  void clearPressed() => _state?._setNumber('pressed', -1);

  /// The tree takes a weight: the canopy's own squash-and-recover, as when
  /// it is tapped. Played when a game is dropped onto it.
  void rustle() => _state?._rustle();
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
    this.asset = kDefaultTreeAsset,
    this.looks = const [],
    this.onlyGrow = true,
  });

  /// True (the search screen's discovery tree) never lets the tree get
  /// smaller: a new result set is a browse, not a collection. False (an
  /// orchard tree) follows [grownTarget] down as well as up ([followGrown]).
  final bool onlyGrow;

  /// Fruit, in slot order (slot 0 is the canopy centre). Only the first
  /// [kTreeSlots] hang.
  final List<Game> games;

  /// Each fruit's look (fruit_look.dart), parallel to [games]. Missing
  /// entries are [FruitLook.plain].
  final List<FruitLook> looks;

  /// How big the tree should be (0..12). See [onlyGrow].
  final int grownTarget;

  /// False shows the empty patch; flipping to true plays seed -> sapling.
  final bool planted;

  final void Function(int slot)? onFruitTap;
  final RiveTreeController? controller;
  final Alignment? alignment;
  final rv.Fit fit;

  /// Which baked tree to show (TreeStyle.asset).
  final String asset;

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
    final asset = widget.asset;
    final file = await loadTreeFile(asset);
    if (!mounted || asset != widget.asset) return;
    if (file == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final c = rv.RiveWidgetController(file,
          artboardSelector: rv.ArtboardSelector.byName('TreeDiscovery'));
      final vm = c.dataBind(rv.DataBind.auto());
      // A restyle swaps files: the old tree stays on screen until the new one
      // is ready, then both go in one frame, so there is never a blank page.
      final oldC = _controller, oldVm = _vm;
      _selected?.removeListener(_onSelected);
      _generation++;
      setState(() {
        _controller = c;
        _vm = vm;
        _failed = false;
      });
      oldC?.dispose();
      oldVm?.dispose();
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
    if (old.asset != widget.asset) {
      // A new look is a new file. It regrows to this tree's size (the file
      // eases `grown` up from 0), which doubles as the restyle's feedback.
      _load();
      return;
    }
    if (old.planted != widget.planted) {
      _vm?.boolean('planted')?.value = widget.planted;
    }
    final before = old.games.take(kTreeSlots).map((g) => g.igdbId).toList();
    final after = _hung.map((g) => g.igdbId).toList();
    if (_sameIds(before, after)) {
      // Same fruit. A game whose state changed (started, finished) repaints
      // its card in place; nothing re-pops.
      for (var i = 0; i < after.length; i++) {
        if (_lookAt(old.looks, i) != _lookAt(widget.looks, i)) {
          _loadCover(i, _generation);
        }
      }
      if (old.grownTarget == widget.grownTarget) return;
    }
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
      _loadCover(i, gen);
    }
    _grownTo = widget.onlyGrow
        ? nextGrown(_grownTo, widget.grownTarget)
        : followGrown(widget.grownTarget);
    _setNumber('grown', treeSize(_grownTo));
    _setNumber('found', hung.length.toDouble());
  }

  static FruitLook _lookAt(List<FruitLook> looks, int i) =>
      i < looks.length ? looks[i] : FruitLook.plain;

  /// Slot [slot]'s card image: the cover with its look baked in, or a
  /// lettered card when there is no cover (fruit_look.dart).
  Future<void> _loadCover(int slot, int gen) async {
    final hung = _hung;
    if (slot >= hung.length) return;
    final game = hung[slot];
    try {
      final png = await fruitPng(game, _lookAt(widget.looks, slot));
      final image = await rv.Factory.rive.decodeImage(png);
      if (!mounted || gen != _generation || image == null) return;
      if (slot >= _hung.length || _hung[slot].igdbId != game.igdbId) return;
      _vm?.image('cover${slot + 1}')?.value = image;
    } catch (_) {
      // Keep the placeholder art; the game is still named everywhere else.
    }
  }

  Timer? _rustleOff;
  void _rustle() {
    _vm?.boolean('rustle')?.value = true;
    _rustleOff?.cancel();
    // The file's rustle is one 440ms beat; clear the flag after it so the
    // next landing can play it again.
    _rustleOff = Timer(const Duration(milliseconds: 460),
        () => _vm?.boolean('rustle')?.value = false);
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
    _rustleOff?.cancel();
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
