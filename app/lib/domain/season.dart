import '../data/enums.dart';
import '../data/models.dart';

/// A count of where the whole collection stands right now.
///
/// This is a snapshot, not a history. There is deliberately no start date, no
/// end date, and nothing that can go down and read as failure: seasons, not
/// streaks, was an explicit rejection of `tolan/home/07`'s streak pill, and a
/// pill only works as encouragement until the day the number resets to zero.
/// A season that ends badly is still a season.
class Season {
  const Season({
    required this.harvested,
    required this.pressed,
    required this.stillGrowing,
    required this.seeds,
  });

  /// Owned and finished.
  final int harvested;

  /// Owned and set aside. Not the same event as finishing, and this is where
  /// the honest, interesting data in the collection actually lives.
  final int pressed;

  /// Owned, and neither finished nor set aside: untouched, installed or
  /// playing. Whatever is left to actually play.
  final int stillGrowing;

  /// Recommended but not owned.
  final int seeds;

  int get total => harvested + pressed + stillGrowing + seeds;
}

/// Summarises the whole collection. Shelved rows are excluded, because
/// shelving is the closest thing this app has to deleting something and a
/// season should describe what the user still considers part of their
/// collection.
///
/// A `released` game (sold, traded, refunded, lapsed) is also excluded from
/// every bucket, on purpose and not by omission. Ownership and progress are
/// independent axes precisely so a sale never erases a completion record, so a
/// released-but-finished game keeps `isHarvested == true` forever in the data.
/// Counting it in `harvested` here would inflate a season with games no
/// longer on the shelf, which is not what "what does my collection look like
/// right now" is asking. The completion record survives; the season snapshot
/// is about the current collection.
///
/// No rate, no percentage, no comparison to a prior period. Those would all
/// invite the same reading a streak invites: that the number can fail.
Season summarise(List<TreeItem> items) {
  var harvested = 0, pressed = 0, stillGrowing = 0, seeds = 0;

  for (final item in items) {
    if (item.entry.shelved) continue;
    if (item.entry.ownership == Ownership.released) continue;

    if (item.isSeed) {
      seeds++;
      continue;
    }

    switch (item.entry.progress) {
      case Progress.finished:
        harvested++;
      case Progress.abandoned:
        pressed++;
      case Progress.untouched:
      case Progress.installed:
      case Progress.playing:
        stillGrowing++;
    }
  }

  return Season(
    harvested: harvested,
    pressed: pressed,
    stillGrowing: stillGrowing,
    seeds: seeds,
  );
}
