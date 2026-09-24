import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/ratings.dart';

void main() {
  TreeItem item(
    int id, {
    Progress progress = Progress.finished,
    int? rating,
  }) =>
      TreeItem(
        game: Game(igdbId: id, title: 'Game $id'),
        entry: Entry(
          igdbId: id,
          ownership: Ownership.owned,
          progress: progress,
          rating: rating,
        ),
        copies: const [],
      );

  test('zero ratings gives a null average, never a division by zero', () {
    final s = summariseRatings([]);
    expect(s.count, 0);
    expect(s.average, isNull);
    expect(s.distribution, isEmpty);
  });

  test('a harvested game with no rating does not count as zero', () {
    final s = summariseRatings([item(1, rating: null)]);
    expect(s.count, 0);
    expect(s.average, isNull,
        reason: 'unrated must not silently become a zero-star rating');
  });

  test('the average of one rating is that rating', () {
    final s = summariseRatings([item(1, rating: 4)]);
    expect(s.count, 1);
    expect(s.average, 4.0);
    expect(s.distribution, {4: 1});
  });

  test('the average of several ratings is correct and the distribution sums',
      () {
    final s = summariseRatings([
      item(1, rating: 5),
      item(2, rating: 5),
      item(3, rating: 3),
    ]);
    expect(s.count, 3);
    expect(s.average, closeTo(13 / 3, 1e-9));
    expect(s.distribution, {5: 2, 3: 1});
  });

  test('an unfinished game with a rating is ignored, defensively', () {
    // This should never happen: the UI only offers a rating at the harvest
    // moment. If it does happen through a hand-edited file, ratings must not
    // count it, because an unfinished game cannot be a harvest.
    final s = summariseRatings([item(1, progress: Progress.playing, rating: 5)]);
    expect(s.count, 0);
  });

  test('a rating outside 1 to 5 is ignored rather than crashing the summary',
      () {
    final s = summariseRatings([
      item(1, rating: 0),
      item(2, rating: 9),
      item(3, rating: -1),
      item(4, rating: 4), // the one valid row
    ]);
    expect(s.count, 1);
    expect(s.average, 4.0);
  });
}
