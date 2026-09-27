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
import '../tokens.dart';

/// A 4:5 card: level and finished count over the orchard, and the app's name.
class OrchardStoryCard extends StatelessWidget {
  const OrchardStoryCard({
    super.key,
    required this.games,
    required this.level,
    required this.trunkName,
  });

  final List<PublishedGame> games;
  final int level;

  /// The group name games on no branch are published under.
  final String trunkName;

  @override
  Widget build(BuildContext context) {
    final harvested = games.where((g) => g.status == Progress.finished).length;
    final trees = portraitFromPublished(games, trunkName);
    final title = TextStyle(
        fontSize: Tokens.type.title,
        fontWeight: FontWeight.w700,
        color: Tokens.palette.text,
        letterSpacing: Tokens.type.trackingTitle);
    final dim = TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.radius.panel),
        child: Stack(fit: StackFit.expand, children: [
          trees.isEmpty
              ? const OrchardPortrait(trees: [])
              : OrchardPortrait(trees: trees),
          Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trees.length == 1 ? trees.first.name : 'My orchard', style: title),
                SizedBox(height: Tokens.space.xxs),
                Text(
                  [
                    games.length == 1 ? '1 game' : '${games.length} games',
                    harvested == 1 ? '1 finished' : '$harvested finished',
                    'level $level',
                  ].join('  ·  '),
                  style: dim,
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text('Ludeck',
                      style: dim.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: Tokens.type.trackingTitle)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
