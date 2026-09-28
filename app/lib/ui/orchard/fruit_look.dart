// How a game looks as fruit: its cover, marked with where the user is with it.
//
// Four looks, and each one is a SHAPE or a material change, never a colour the
// user has to learn (ripeness was removed for exactly that on 2026-09-24):
//
//   bud        recommended, not owned yet: the cover is drained of colour and
//              dimmed, the way a bud is the fruit before it has its colour
//   plain      owned, not started or installed: the cover as it is
//   playing    in hand: a play mark in the corner
//   harvested  finished: a gold rim and a check. Gold keeps its ONE meaning.
//
// The look is baked into the 240x320 image the Rive card shows, so the tree
// file needs no per-card state, and the ground tray and the card in your hand
// use the very same pixels. A game with no cover gets a lettered card instead
// of the file's generic placeholder, which read as a failed image.

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../tokens.dart';

/// Pixel size of a fruit image (the Rive card's image slot).
const int kFruitW = 240, kFruitH = 320;

enum FruitLook { bud, plain, playing, harvested }

/// Where the user is with [item], as fruit.
FruitLook lookOf(TreeItem item) {
  if (item.isSeed) return FruitLook.bud;
  return switch (item.entry.progress) {
    Progress.finished => FruitLook.harvested,
    Progress.playing => FruitLook.playing,
    _ => FruitLook.plain,
  };
}

/// Spoken form of a look, for the labels that carry it to a screen reader.
String lookLabel(FruitLook look) => switch (look) {
      FruitLook.bud => 'not owned yet',
      FruitLook.plain => 'not started',
      FruitLook.playing => 'playing',
      FruitLook.harvested => 'finished',
    };

// Bounded: one entry per game and look seen this run.
final LinkedHashMap<String, Future<Uint8List>> _cache = LinkedHashMap();
final Map<String, Uint8List> _done = {};
const int _cacheMax = 160;

String _key(Game game, FruitLook look) =>
    '${game.igdbId}|${game.coverUrl}|${look.name}';

/// The image if it is already built, else null. For a widget that must not
/// show an empty frame (the card lifted into your hand).
Uint8List? fruitPngNow(Game game, FruitLook look) => _done[_key(game, look)];

/// [game] as a [look] fruit image (PNG, [kFruitW]x[kFruitH]). Cached, so the
/// tray, the card in your hand and the tree share one download and one encode.
/// Never fails: an unreachable cover becomes the lettered card.
Future<Uint8List> fruitPng(Game game, FruitLook look) {
  final key = _key(game, look);
  final hit = _cache.remove(key);
  if (hit != null) return _cache[key] = hit; // most recent last
  if (_cache.length >= _cacheMax) {
    final oldest = _cache.keys.first;
    _cache.remove(oldest);
    _done.remove(oldest);
  }
  final f = _build(game, look).then((png) {
    if (_cache.containsKey(key)) _done[key] = png;
    return png;
  });
  return _cache[key] = f;
}

final Map<String, Future<Uint8List?>> _downloads = {};

Future<Uint8List?> _download(String url) => _downloads[url] ??= () async {
      try {
        final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
        return data.buffer.asUint8List();
      } catch (_) {
        _downloads.remove(url); // try again next time rather than never
        return null;
      }
    }();

Future<Uint8List> _build(Game game, FruitLook look) async {
  final url = game.coverUrl;
  ui.Image? cover;
  if (url != null && url.isNotEmpty) {
    final bytes = await _download(url);
    if (bytes != null) {
      try {
        cover = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
      } catch (_) {
        cover = null;
      }
    }
  }
  return composeFruit(cover, game.title, look);
}

/// Draw [cover] (or a lettered card for [title]) with [look]'s marks, as PNG.
/// Pure drawing, public so a test can render every look.
Future<Uint8List> composeFruit(ui.Image? cover, String title, FruitLook look) async {
  const w = kFruitW * 1.0, h = kFruitH * 1.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final full = const Rect.fromLTWH(0, 0, w, h);

  final base = Paint()..filterQuality = FilterQuality.medium;
  if (look == FruitLook.bud) base.colorFilter = const ColorFilter.matrix(_budMatrix);
  if (cover != null) {
    final sw = cover.width.toDouble(), sh = cover.height.toDouble();
    final s = math.max(w / sw, h / sh);
    final cw = w / s, ch = h / s;
    c.drawImageRect(cover, Rect.fromLTWH((sw - cw) / 2, (sh - ch) / 2, cw, ch),
        full, base);
  } else {
    _lettered(c, full, title, base.colorFilter);
  }

  final gold = Tokens.palette.accent, ink = Tokens.palette.bg;
  final text = Tokens.palette.text;
  const badge = Offset(w - 54, h - 54);
  const r = 40.0;
  switch (look) {
    case FruitLook.bud:
      c.drawRect(full, Paint()..color = ink.withValues(alpha: 0.30));
    case FruitLook.plain:
      break;
    case FruitLook.playing:
      c.drawCircle(badge, r, Paint()..color = ink.withValues(alpha: 0.82));
      c.drawCircle(
          badge,
          r - 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = text);
      c.drawPath(
          Path()
            ..moveTo(badge.dx - 11, badge.dy - 17)
            ..lineTo(badge.dx + 17, badge.dy)
            ..lineTo(badge.dx - 11, badge.dy + 17)
            ..close(),
          Paint()..color = text);
    case FruitLook.harvested:
      c.drawRRect(
          RRect.fromRectAndRadius(full.deflate(8), const Radius.circular(14)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..color = gold);
      c.drawCircle(badge, r, Paint()..color = gold);
      c.drawPath(
          Path()
            ..moveTo(badge.dx - 17, badge.dy + 1)
            ..lineTo(badge.dx - 5, badge.dy + 13)
            ..lineTo(badge.dx + 18, badge.dy - 12),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = ink);
  }

  final img = await rec.endRecording().toImage(kFruitW, kFruitH);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  cover?.dispose();
  return data!.buffer.asUint8List();
}

/// Saturation 0.15, so a bud keeps a trace of its cover's colour.
const List<double> _budMatrix = [
  0.3485, 0.6095, 0.0420, 0, 0, //
  0.1805, 0.7775, 0.0420, 0, 0, //
  0.1805, 0.6095, 0.2100, 0, 0, //
  0, 0, 0, 1, 0,
];

void _lettered(Canvas c, Rect r, String title, ColorFilter? filter) {
  final cm = Tokens.cosmos;
  c.drawRect(
      r,
      Paint()
        ..colorFilter = filter
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cm.hillTop, cm.hillDeep],
        ).createShader(r));
  final letter = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
  final tp = TextPainter(
    text: TextSpan(
        text: letter,
        // A TextPainter on a canvas inherits no theme: name the family.
        style: TextStyle(
            fontFamily: Tokens.type.displayFamily,
            fontSize: 132,
            fontWeight: FontWeight.w800,
            color: Tokens.palette.text.withValues(alpha: 0.92))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, r.center - Offset(tp.width / 2, tp.height / 2 + 18));
  final name = TextPainter(
    text: TextSpan(
        text: title,
        style: TextStyle(
            fontFamily: Tokens.type.ui,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Tokens.palette.textDim)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: r.width - 36);
  name.paint(c, Offset(r.center.dx - name.width / 2, r.bottom - 30 - name.height));
}
