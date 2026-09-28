// The shareable story: the collection as its ORCHARD.
//
// It replaced the roadmap card (2026-09-27). A friend who sees it recognises
// the trees they will get when they open the app: the same meadow, the same
// trees in their own colours, the same fruit marked the same way (a gold rim
// for a finished game, a play mark for one in hand).
//
// PRIVACY: it renders ONLY `PublishedGame` (title, cover, status, branch
// name). It never touches recommendedBy, notes, or a source's channel -- there
// is no such field on the shape it is given, exactly as publish_export
// guarantees.

import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../services/social/social_backend.dart';
import '../orchard/orchard_portrait.dart';
import '../orchard/tree_style.dart';
import '../tokens.dart';

/// A 4:5 card: level and finished count over the orchard, and the app's name.
class OrchardStoryCard extends StatelessWidget {
  const OrchardStoryCard({
    super.key,
    required this.games,
    required this.level,
    required this.trunkName,
    this.styles = const {},
  });

  final List<PublishedGame> games;
  final int level;

  /// The group name games on no branch are published under.
  final String trunkName;

  /// Each tree's own look by name, so the card matches home.
  final Map<String, TreeStyle> styles;

  @override
  Widget build(BuildContext context) {
    final harvested = games.where((g) => g.status == Progress.finished).length;
    final playing = games.where((g) => g.status == Progress.playing).length;
    final trees = portraitFromPublished(games, trunkName, styles: styles);
    final t = Tokens.palette;
    final n = games.length;

    // Hierarchy, read top to bottom in one pass (2026-09-28, replacing a
    // title and a three-number grid stacked over the sky, which put the
    // loudest type on top of the trees):
    //   1. the orchard, alone in its sky: the picture is the message;
    //   2. one sentence in the soil: how many games it holds;
    //   3. one quiet line: what has come of them;
    //   4. the app's name, small, opposite the eyebrow in the empty sky.
    // Text sits on the dark ground, never over the trees, so it keeps its
    // contrast whatever the blossom colours are.
    final facts = [
      if (harvested > 0) '$harvested finished',
      if (playing > 0) '$playing playing now',
      'level $level',
    ].join('  ·  ');
    // The trunk group's name is internal (games on no tree), not a title.
    final eyebrow = trees.length == 1 && trees.first.name != trunkName
        ? trees.first.name
        : 'My orchard';

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(Tokens.radius.sheet),
        child: ColoredBox(
          color: Tokens.cosmos.hillDeep,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                OrchardPortrait(trees: trees, showNames: trees.length > 1),
                Positioned(
                  left: Tokens.space.md,
                  right: Tokens.space.md,
                  top: Tokens.space.md,
                  child: Row(children: [
                    Expanded(
                      child: Text(eyebrow.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Tokens.type.caption,
                              fontWeight: FontWeight.w700,
                              letterSpacing: Tokens.type.trackingEyebrow,
                              color: t.text.withValues(alpha: 0.72))),
                    ),
                    SizedBox(width: Tokens.space.sm),
                    // The wordmark, in the headline face so it reads as a
                    // mark and not as another caption.
                    Text('Ludeck',
                        style: TextStyle(
                            fontFamily: Tokens.type.displayFamily,
                            fontSize: Tokens.type.body,
                            fontWeight: FontWeight.w800,
                            letterSpacing: Tokens.type.trackingTitle,
                            color: t.text.withValues(alpha: 0.7))),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  Tokens.space.md, 0, Tokens.space.md, Tokens.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    n == 1 ? '$n game in my orchard' : '$n games in my orchard',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.title,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                        letterSpacing: Tokens.type.trackingTitle,
                        height: 1.15),
                  ),
                  SizedBox(height: Tokens.space.xxs),
                  Text(facts,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Tokens.type.caption, color: t.textDim)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
