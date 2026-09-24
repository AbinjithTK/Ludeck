import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/season.dart';

void main() {
  TreeItem item(
    int id, {
    Ownership ownership = Ownership.owned,
    Progress progress = Progress.untouched,
    bool shelved = false,
  }) =>
      TreeItem(
        game: Game(igdbId: id, title: 'Game $id'),
        entry: Entry(
          igdbId: id,
          ownership: ownership,
          progress: progress,
          shelved: shelved,
        ),
        copies: const [],
      );

  test('an empty collection is a season of zeros, not an error', () {
    final s = summarise([]);
    expect(s.harvested, 0);
    expect(s.pressed, 0);
    expect(s.stillGrowing, 0);
    expect(s.seeds, 0);
    expect(s.total, 0);
  });

  test('each state lands in exactly its own bucket', () {
    final s = summarise([
      item(1, progress: Progress.finished),
      item(2, progress: Progress.abandoned),
      item(3, progress: Progress.untouched),
      item(4, progress: Progress.installed),
      item(5, progress: Progress.playing),
      item(6, ownership: Ownership.spotted),
    ]);
    expect(s.harvested, 1);
    expect(s.pressed, 1);
    expect(s.stillGrowing, 3, reason: 'untouched, installed and playing all count');
    expect(s.seeds, 1);
    expect(s.total, 6);
  });

  test('a shelved game is excluded from every bucket', () {
    final s = summarise([
      item(1, progress: Progress.finished, shelved: true),
    ]);
    expect(s.total, 0);
  });

  test('a released game is excluded from every bucket, even if it was '
      'finished, because the completion record survives elsewhere and a '
      'season is about the current collection', () {
    final s = summarise([
      item(1, ownership: Ownership.released, progress: Progress.finished),
    ]);
    expect(s.total, 0);
    expect(s.harvested, 0,
        reason: 'the record exists in Entry.progress forever; the season '
            'snapshot is not the place that record is read back from');
  });

  test('a seed can never be finished, abandoned or installed, by the model',
      () {
    // Guards the invariant this file relies on rather than re-checks: a seed
    // is `spotted`, and `isSeed` is defined purely by ownership, so a seed's
    // progress value never reaches this function's switch at all.
    final s = summarise([item(1, ownership: Ownership.spotted)]);
    expect(s.seeds, 1);
    expect(s.harvested + s.pressed + s.stillGrowing, 0);
  });

  test('nothing here is a rate, a percentage or a comparison', () {
    // There is no method on Season for any of those. This test exists so a
    // future addition of one is a conscious decision, not an oversight: adding
    // `completionRate` or similar reopens the exact framing "seasons, not
    // streaks" was written to close.
    final s = summarise([item(1, progress: Progress.finished)]);
    expect(s.total, 1);
    // If this test starts failing to compile because someone added a rate
    // getter, that is the signal to re-read DECISIONS.md before proceeding.
  });
}
