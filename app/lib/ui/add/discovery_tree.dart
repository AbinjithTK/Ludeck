// The game-discovery moment on the Add screen: search results hang on a full
// Rive tree as cover cards. A thin wrapper over the shared [RiveTree].
//
// Decorative duplicate of the result list below it, so it is excluded from
// semantics: every card is also a labelled, tappable row in the list.
// Reduced motion: not shown; the list is the content.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../orchard/rive_tree.dart';

export '../orchard/rive_tree.dart' show canopyAlignment, kTreeSlots, nextGrown;

/// Results shown as cards (the file has room for [kTreeSlots]).
const int kDiscoverySlots = 6;

class DiscoveryTree extends StatelessWidget {
  const DiscoveryTree({super.key, required this.games, this.onPick});

  final List<Game> games;
  final void Function(Game game)? onPick;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    final shown = games.take(kDiscoverySlots).toList();
    return ExcludeSemantics(
      child: RiveTree(
        games: shown,
        // A full tree as soon as anything is found: results are a harvest to
        // browse, not a collection's size. Never shrinks back (nextGrown).
        grownTarget: shown.isEmpty ? 0 : kTreeSlots,
        onFruitTap: (slot) {
          if (slot < shown.length) onPick?.call(shown[slot]);
        },
      ),
    );
  }
}
