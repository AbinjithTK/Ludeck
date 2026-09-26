// The game-discovery moment: a tree that grows as search results arrive and
// hangs each found game on its canopy as a cover card.
//
// The motion lives in the Rive file (rive/tree, built from the designer's
// tree). This widget only feeds it: `found` = how many results (max 6),
// `cover1..6` = their cover art, and it reads `selected` back when a card is
// tapped. See rive/AGENTS.md for the contract.
//
// Decorative duplicate of the result list below it, so it is excluded from
// semantics: every card is also a labelled, tappable row in the list.
//
// Reduced motion: not shown at all. The file's growth and pops ARE the
// content; a frozen tree adds nothing the list does not already say.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';

/// Cards the file has room for.
const int kDiscoverySlots = 6;

/// Pixel size the file's cover slots are drawn from (see rive/tree).
const int kCoverW = 240, kCoverH = 320;

/// Artboard geometry, for framing the canopy in a shorter box.
const double _artW = 412, _artH = 732;

/// Top of the full-grown canopy in artboard units, less a little headroom.
const double _canopyTop = 185;

class DiscoveryTree extends StatefulWidget {
  const DiscoveryTree({super.key, required this.games, this.onPick});

  /// The current results. The first [kDiscoverySlots] become cards.
  final List<Game> games;

  /// A card was tapped.
  final void Function(Game game)? onPick;

  @override
  State<DiscoveryTree> createState() => _DiscoveryTreeState();
}

class _DiscoveryTreeState extends State<DiscoveryTree> {
  /// Loaded here, not by RiveWidgetBuilder: the builder's own load reports a
  /// failure as an unhandled async error, and a missing native library (the
  /// headless test host, an unsupported platform) must degrade to nothing.
  rv.FileLoader? _loader;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await rv.File.asset('assets/rive/tree_discovery.riv',
          riveFactory: rv.Factory.rive);
      if (!mounted) {
        file?.dispose();
        return;
      }
      setState(() {
        if (file == null) {
          _failed = true;
        } else {
          _loader = rv.FileLoader.fromFile(file, riveFactory: rv.Factory.rive);
        }
      });
    } catch (e) {
      debugPrint('DiscoveryTree: Rive unavailable ($e); showing the list only');
      if (mounted) setState(() => _failed = true);
    }
  }

  rv.ViewModelInstance? _vm;
  rv.ViewModelInstanceNumber? _found;
  rv.ViewModelInstanceNumber? _selected;
  Timer? _regrow;

  /// Bumped per result set, so a slow cover from an old search never lands
  /// on a card that now shows a different game.
  int _generation = 0;

  List<Game> get _shown => widget.games.take(kDiscoverySlots).toList();

  @override
  void didUpdateWidget(DiscoveryTree old) {
    super.didUpdateWidget(old);
    final before = old.games.take(kDiscoverySlots).map((g) => g.igdbId).toList();
    final after = _shown.map((g) => g.igdbId).toList();
    if (_listEquals(before, after)) return;
    // A new result set: fold the tree back, then grow it again so the new
    // games are discovered fresh rather than swapped onto old cards.
    _generation++;
    _selected?.value = -1;
    _found?.value = 0;
    _regrow?.cancel();
    _regrow = Timer(const Duration(milliseconds: 260), _feed);
  }

  void _onLoaded(rv.RiveLoaded state) {
    final vm = state.viewModelInstance;
    if (vm == null) return;
    _vm = vm;
    _found = vm.number('found');
    _selected = vm.number('selected');
    _selected?.addListener(_onSelected);
    _feed();
  }

  void _feed() {
    if (!mounted || _vm == null) return;
    final games = _shown;
    final gen = _generation;
    for (var i = 0; i < games.length; i++) {
      final url = games[i].coverUrl;
      if (url != null && url.isNotEmpty) _loadCover(i, url, gen);
    }
    _found?.value = games.length.toDouble();
  }

  Future<void> _loadCover(int slot, String url, int gen) async {
    try {
      final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final png = await coverFitPng(bytes.buffer.asUint8List());
      final image = await rv.Factory.rive.decodeImage(png);
      if (!mounted || gen != _generation || image == null) return;
      _vm?.image('cover${slot + 1}')?.value = image;
    } catch (_) {
      // Keep the file's placeholder art. A missing cover is not an error the
      // user can act on, and the list row below still names the game.
    }
  }

  void _onSelected(double value) {
    final i = value.round();
    final games = _shown;
    if (i >= 0 && i < games.length) widget.onPick?.call(games[i]);
  }

  @override
  void dispose() {
    _regrow?.cancel();
    _selected?.removeListener(_onSelected);
    _loader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    final loader = _loader;
    if (_failed || loader == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, box) {
        return rv.RiveWidgetBuilder(
          fileLoader: loader,
          artboardSelector: rv.ArtboardSelector.byName('TreeDiscovery'),
          dataBind: rv.DataBind.auto(),
          onLoaded: _onLoaded,
          builder: (context, state) => switch (state) {
            rv.RiveLoaded() => rv.RiveWidget(
                controller: state.controller,
                fit: rv.Fit.cover,
                alignment: canopyAlignment(box.maxWidth, box.maxHeight),
                // Taps between cards fall through to the page.
                hitTestBehavior: rv.RiveHitTestBehavior.translucent,
              ),
            // Loading, or no native Rive library (headless tests): nothing.
            // The result list is the content; the tree is the celebration.
            _ => const SizedBox.shrink(),
          },
        );
      }),
    );
  }
}

/// Vertical alignment that puts the grown canopy at the top of a [w]x[h] box
/// when the 412x732 artboard is scaled to cover it.
///
/// Fit.cover scales by the larger ratio; if that is the width, the artboard
/// overflows vertically and `alignment.y` picks which band is visible. Pure
/// arithmetic so it can be tested without a device.
Alignment canopyAlignment(double w, double h) {
  if (w <= 0 || h <= 0) return Alignment.center;
  final scale = (w / _artW) > (h / _artH) ? w / _artW : h / _artH;
  final visible = h / scale;
  final overflow = _artH - visible;
  if (overflow <= 0) return Alignment.center;
  final y = (2 * _canopyTop / overflow - 1).clamp(-1.0, 1.0);
  return Alignment(0, y);
}

/// Scale-and-crop [bytes] to exactly [kCoverW]x[kCoverH] (BoxFit.cover), as
/// PNG, so every cover fills its card identically whatever the source size.
Future<Uint8List> coverFitPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final src = (await codec.getNextFrame()).image;
  final sw = src.width.toDouble(), sh = src.height.toDouble();
  final scale = (kCoverW / sw) > (kCoverH / sh) ? kCoverW / sw : kCoverH / sh;
  final cw = kCoverW / scale, ch = kCoverH / scale;
  final from = Rect.fromLTWH((sw - cw) / 2, (sh - ch) / 2, cw, ch);
  final to = Rect.fromLTWH(0, 0, kCoverW.toDouble(), kCoverH.toDouble());
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(src, from, to,
      Paint()..filterQuality = FilterQuality.medium);
  final out = await rec.endRecording().toImage(kCoverW, kCoverH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  src.dispose();
  out.dispose();
  return data!.buffer.asUint8List();
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
