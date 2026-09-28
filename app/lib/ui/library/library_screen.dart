import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../../state/ludeck_store.dart';
import '../collection/collection_view.dart';
import '../gamified/primitives.dart';

import '../tokens.dart';

/// The whole collection as a list, reached from the navigation pill.
///
/// `CollectionView` already existed and was already tested -- it was simply not
/// reachable from anywhere. It was built as the list-shaped counterpart to the
/// tree and then never given a route, which is the same class of defect as the
/// social surface being four taps deep: working code with no door.
///
/// This is a thin wrapper on purpose. It supplies the store, the cover cache and
/// the two insets, and does nothing else -- the grouping, the sections and the
/// spoken labels all stay in the view where their tests already are.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.onSelect,
    this.coverCache,
  });

  /// Opens the status sheet, which is also where a game is filed onto a branch.
  /// Passed in rather than rebuilt here so the sheet stays in one place.
  final ValueChanged<TreeItem> onSelect;

  final CoverArtCache? coverCache;

  /// The library lists everything you track: owned GAMES and wishlist BUDS.
  /// The header headline counts only games on the tree (owned), so a bare
  /// total here would read as a contradiction of it -- 10 vs 8. Breaking the
  /// count out (8 games, 2 buds) makes the two numbers agree instead of fight,
  /// and honours DECISIONS.md's rule that a bud is a wish, not a game.
  static String _libraryTitle(List<TreeItem> items) {
    if (items.isEmpty) return 'Your library';
    final buds = items.where((i) => i.isSeed).length;
    final games = items.length - buds;
    if (buds == 0) {
      return 'Your library \u00B7 $games ${games == 1 ? 'game' : 'games'}';
    }
    return 'Your library \u00B7 $games ${games == 1 ? 'game' : 'games'}, '
        '$buds on your wishlist';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore>();
    final items = store.items ?? const <TreeItem>[];

    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                Tokens.space.md,
                MediaQuery.of(context).padding.top + Tokens.space.md,
                Tokens.space.md,
                Tokens.space.sm,
              ),
              child: Row(children: [
                // Pushed from the orchard's top buttons: its way back.
                if (Navigator.of(context).canPop())
                  BackButton(color: Tokens.palette.text),
                Expanded(child: Text(
                _libraryTitle(items),
                style: TextStyle(
                  fontFamily: Tokens.type.displayFamily,
                  fontSize: Tokens.type.title,
                  letterSpacing: Tokens.type.trackingTitle,
                  color: Tokens.palette.text,
                ),
              )),
              ]),
            ),
            Expanded(
              child: CollectionView(
                items: items,
                branches: store.branches,
                placements: store.placements,
                coverCache: coverCache,
                onCoverFound: store.applyCoverUrl,
                onSelect: onSelect,
                onHold: onSelect,
                topInset: 0,
                // The pill floats OVER this list, so the list has to reserve its
                // height or the last rows scroll underneath it. A plain margin was
                // not enough: on device the final row and a section header sat
                // behind the pill, which reads as a rendering fault rather than as
                // a list that continues.
                bottomInset: MediaQuery.of(context).padding.bottom +
                    Tokens.space.md * 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
