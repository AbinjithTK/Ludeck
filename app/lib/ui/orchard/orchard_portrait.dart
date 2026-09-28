// A still portrait of the orchard: up to three trees standing on one meadow
// under the night sky, their games hanging as the same fruit the home screen
// shows. The profile's avatar and the share card are both this picture, so
// what a friend sees shared is what the owner sees at home.
//
// It replaced the winding roadmap on both (2026-09-27): the orchard is the
// app's metaphor now, and a roadmap on the profile and the card was a third
// picture of the same collection.

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rv;

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/social/social_backend.dart';
import '../tokens.dart';
import 'fruit_look.dart';
import 'meadow.dart';
import 'rive_tree.dart';
import 'tree_style.dart';

/// One tree in a portrait.
typedef PortraitTree = ({
  String name,
  List<Game> games,
  List<FruitLook> looks,
  TreeStyle style,
});

/// Most trees a portrait holds: past three, each is too small to read.
const int kPortraitTrees = 3;

/// The trees a portrait shows: the [kPortraitTrees] fullest, in their order.
List<PortraitTree> portraitPick(List<PortraitTree> all) {
  if (all.length <= kPortraitTrees) return all;
  final keep = ([...all]..sort((a, b) => b.games.length.compareTo(a.games.length)))
      .take(kPortraitTrees)
      .toSet();
  return all.where(keep.contains).toList();
}

/// A shared collection, as portrait trees: one per branch name, in order.
/// Games on no branch only make a tree when there is no other.
List<PortraitTree> portraitFromPublished(
    List<PublishedGame> games, String trunkName,
    {Map<String, TreeStyle> styles = const {}}) {
  final byName = <String, List<PublishedGame>>{};
  for (final g in games) {
    (byName[g.branchName] ??= []).add(g);
  }
  if (byName.length > 1) byName.remove(trunkName);
  var i = 0;
  return [
    for (final e in byName.entries)
      (
        name: e.key,
        games: [
          for (final g in e.value)
            Game(igdbId: g.igdbId, title: g.title, coverUrl: g.coverUrl)
        ],
        looks: [
          for (final g in e.value)
            switch (g.status) {
              Progress.finished => FruitLook.harvested,
              Progress.playing => FruitLook.playing,
              _ => FruitLook.plain,
            }
        ],
        // The owner's own colours when known (the share card), so the card
        // shows the trees they see at home; a visitor's copy falls back.
        style: styles[e.key] ?? TreeStyle.defaultFor(i++),
      )
  ];
}

/// How far a trunk's foot sinks below the hill surface (px), so the front
/// grass closes over it and the tree stands IN the meadow, not on a line.
const double kFootSink = 3;

/// Where each of [trees] stands in a portrait of [size] whose soil line is
/// [soil] px from the bottom. One slot per tree; the meadow's ridge has one
/// crest per slot ([MeadowBackPainter.period] = slot width), and each trunk's
/// foot is moved onto that crest and [kFootSink] into it.
///
/// Before 2026-09-28 the ridge had ONE crest, at the picture's centre, while
/// two or three trees stood at slot centres where the ridge dips: every tree
/// hung above the hill ("these trees are in air"). Pure, so a test pins it.
List<Rect> portraitFrames(Size size, double soil, List<int> gameCounts) {
  final groundY = size.height - soil;
  final n = gameCounts.isEmpty ? 1 : gameCounts.length;
  final slotW = size.width / n;
  return [
    for (var i = 0; i < gameCounts.length; i++)
      () {
        // A lone tree gets headroom for a title; several stand closer.
        final f = treeFrame(Size(slotW, size.height), groundY,
            treeZoom(gameCounts[i]),
            headroom: size.height * (n == 1 ? 0.06 : 0.12));
        final s = f.width / kTreeArtW;
        final footX = slotW * (i + 0.5); // the crest
        final footY = ridgeY(footX, slotW, groundY) + kFootSink;
        return f.shift(Offset(footX - (f.left + kTreeBaseX * s),
            footY - (f.top + kTreeBaseY * s)));
      }()
  ];
}

class OrchardPortrait extends StatelessWidget {
  const OrchardPortrait({super.key, required this.trees, this.showNames = true});

  final List<PortraitTree> trees;
  final bool showNames;

  static final ValueNotifier<double> _still = ValueNotifier(0);

  @override
  Widget build(BuildContext context) {
    final shown = portraitPick(trees);
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final soil = size.height * 0.2; // soil line, from the bottom
      final groundY = size.height - soil;
      final n = shown.isEmpty ? 1 : shown.length;
      final slotW = size.width / n;
      final frames =
          portraitFrames(size, soil, [for (final t in shown) t.games.length]);
      return ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(
              painter: MeadowBackPainter(
                  scroll: _still, groundFromBottom: soil, period: slotW)),
          CustomPaint(
              painter: MeadowGrassPainter(
                  scroll: _still, groundFromBottom: soil, period: slotW)),
          for (var i = 0; i < shown.length; i++) ...() {
            final t = shown[i];
            final frame = frames[i];
            return [
              CustomPaint(
                  painter: GroundContactPainter(
                      tree: frame, groundY: groundY, pageIndex: 0, period: slotW)),
              Positioned.fromRect(
                rect: frame,
                child: IgnorePointer(
                  // A picture: tapping it must not select fruit.
                  child: RiveTree(
                  games: t.games,
                  looks: t.looks,
                  grownTarget: t.games.length,
                  fit: rv.Fit.contain,
                  alignment: Alignment.center,
                  asset: t.style.asset,
                )),
              ),
              if (showNames)
                Positioned(
                  left: slotW * i,
                  width: slotW,
                  top: groundY + soil * 0.28,
                  child: Text(t.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Tokens.type.caption,
                          fontWeight: FontWeight.w600,
                          color: Tokens.palette.textDim)),
                ),
            ];
          }(),
          IgnorePointer(
            child: CustomPaint(
                painter: MeadowFrontPainter(
                    scroll: _still, groundFromBottom: soil, period: slotW)),
          ),
        ]),
      );
    });
  }
}
