import '../data/models.dart';

/// How the harvested part of the collection was rated.
///
/// Only harvested games count, and only when they carry a rating: rating an
/// unfinished game should never happen (the UI only offers it at the harvest
/// moment), but this file does not trust that and quietly ignores anything
/// that slipped through rather than letting one bad row break the summary.
class RatingSummary {
  const RatingSummary({
    required this.count,
    required this.average,
    required this.distribution,
  });

  /// How many harvested games carry a rating.
  final int count;

  /// Null when [count] is zero. Never computed as 0/0.
  final double? average;

  /// Rating value (1 to 5) to how many games hold that value. A value that is
  /// never used is simply absent from the map rather than present at zero.
  final Map<int, int> distribution;
}

/// Ratings are 1 to 5 inclusive, matching `Repository.setRating`'s validation.
/// Anything outside that range is ignored rather than thrown on, because this
/// function reads data that already made it into memory and a bad row here
/// must not take a summary screen down; `Repository.loadDetailed` is the layer
/// responsible for catching a row that bad before it gets this far.
RatingSummary summariseRatings(List<TreeItem> items) {
  final distribution = <int, int>{};
  var sum = 0;
  var count = 0;

  for (final item in items) {
    if (!item.isHarvested) continue;
    final rating = item.entry.rating;
    if (rating == null) continue;
    if (rating < 1 || rating > 5) continue;

    distribution[rating] = (distribution[rating] ?? 0) + 1;
    sum += rating;
    count++;
  }

  return RatingSummary(
    count: count,
    average: count == 0 ? null : sum / count,
    distribution: distribution,
  );
}
