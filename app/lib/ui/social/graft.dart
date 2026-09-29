// Taking a game from a friend and growing it on your own tree: a graft.
//
// One function, so the friend's orchard, the Lately list and a seed in your
// inbox all plant the same way: into the wishlist (spotted, untouched), with
// the friend's handle as `recommendedBy`.
//
// This is the INTAKE side of invariant 10 (see scripts/check.ps1 rule 10):
// receiving a recommendation is how `recommendedBy` gets filled in. It never
// travels back out: publishing goes through toPublished, and activity posts
// carry title, cover and rating only.

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../state/ludeck_store.dart';

Future<void> graftFromFriend(
  LudeckStore store, {
  required int igdbId,
  required String title,
  String? coverUrl,
  required String fromHandle,
}) =>
    store.addShared(
      TreeItem(
        // Built straight from what was seen, with no second catalogue round
        // trip and no risk of resolving to a different game than the one
        // tapped.
        game: Game(igdbId: igdbId, title: title, coverUrl: coverUrl),
        entry: Entry(
          igdbId: igdbId,
          // A recommendation, not a purchase: it lands in the wishlist.
          ownership: Ownership.spotted,
          progress: Progress.untouched,
          recommendedBy: fromHandle,
        ),
        copies: const [],
      ),
      Source(
        igdbId: igdbId,
        // The source is another Ludeck tree, and there is no SourceKind for
        // that. `web` is the closest honest fit among the frozen values;
        // `manual` because the person tapped it, so nothing was guessed.
        kind: SourceKind.web,
        matchMethod: MatchMethod.manual,
        addedAt: DateTime.now(),
      ),
    );
