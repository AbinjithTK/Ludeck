// The ONE place a private collection becomes a public payload.
//
// This function is the privacy invariant made executable. Everything the app
// publishes flows through `toPublished`, and it constructs `PublishedGame` from
// exactly four collection facts -- title, cover, status, rating -- plus the
// branch NAME. It reads `TreeItem.entry.recommendedBy`, `entry.note` and the
// game's sources NOWHERE, so those third-party names cannot escape even by
// accident: there is no line here that touches them.
//
// docs/DECISIONS.md invariant 10 / scripts/check.ps1 rule 10. This file is named
// with `export` so the checker scans it; it names none of the forbidden columns.

import '../../data/models.dart';
import 'social_backend.dart';

/// Project owned, placed games into their public form for one branch.
///
/// Seeds (spotted, not owned) are excluded: a seed is something you were told
/// about and may never own, so it is doubly not yours to publish -- it is not in
/// your collection and it usually carries `recommendedBy`. Only games you own
/// and have placed on a branch appear on a published tree.
List<PublishedGame> toPublished(
  Iterable<TreeItem> items,
  String branchName,
) {
  final out = <PublishedGame>[];
  for (final item in items) {
    if (item.isSeed) continue;
    out.add(PublishedGame(
      igdbId: item.game.igdbId,
      title: item.game.title,
      coverUrl: item.game.coverUrl,
      status: item.entry.progress,
      rating: item.entry.rating,
      branchName: branchName,
    ));
  }
  return out;
}
