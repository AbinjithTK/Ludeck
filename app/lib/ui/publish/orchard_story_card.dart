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
    final trees = portraitFromPublished(games, trunkName, styles: styles);
    final t = Tokens.palette;
    // Hierarchy: the orchard is the picture; one line of title over the sky;
    // the three numbers that say what it holds; the name of the app, small.
    // No frame, no boxes: the sky runs to the card's edge.
    Widget stat(int n, String word) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$n',
                style: TextStyle(
                    fontSize: Tokens.type.title,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                    height: 1.05,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(word, style: TextStyle(fontSize: Tokens.type.caption, color: t.textDim)),
          ],
        );
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(Tokens.radius.sheet),
        child: Stack(fit: StackFit.expand, children: [
          trees.isEmpty
              ? const OrchardPortrait(trees: [])
              : OrchardPortrait(trees: trees),
          Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(trees.length == 1 ? trees.first.name : 'My orchard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Tokens.type.display,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                            letterSpacing: Tokens.type.trackingDisplay,
                            height: Tokens.type.leadingDisplay)),
                  ),
                  // Top right, in the empty sky: at the foot it sat on the
                  // trees' name labels.
                  Padding(
                    padding: EdgeInsets.only(top: Tokens.space.xxs),
                    child: Text('Ludeck',
                        style: TextStyle(
                            fontSize: Tokens.type.caption,
                            fontWeight: FontWeight.w700,
                            color: t.text.withValues(alpha: 0.7),
                            letterSpacing: 1.2)),
                  ),
                ]),
                SizedBox(height: Tokens.space.sm),
                Wrap(spacing: Tokens.space.lg, runSpacing: Tokens.space.xs, children: [
                  stat(games.length, games.length == 1 ? 'game' : 'games'),
                  stat(harvested, 'finished'),
                  stat(level, 'level'),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
