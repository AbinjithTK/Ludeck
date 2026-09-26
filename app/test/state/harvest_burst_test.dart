// The harvest-burst signal: fired on the real transition into finished, once.
//
// Stage 5 celebration animations are driven by store events, not demo triggers.
// These lock the event contract: it fires on the TRANSITION (not the state),
// it is one-shot (consumed, never replays), and a level-crossing harvest also
// flags a level-up. Plain test() -- no widget, no FakeAsync (see CONSTRAINTS.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/domain/level.dart';
import 'package:ludeck/state/ludeck_store.dart';

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
    store = LudeckStore(repo);
  });

  tearDown(() async {
    store.dispose();
    await repo.close();
  });

  TreeItem owned(int id, String title, {Progress progress = Progress.playing}) =>
      TreeItem(
        game: Game(igdbId: id, title: title),
        entry: Entry(igdbId: id, ownership: Ownership.owned, progress: progress),
        copies: const [],
      );

  test('finishing a game flags it as just harvested', () async {
    await store.upsert(owned(1, 'Hades'));
    expect(store.justHarvested, isNull, reason: 'nothing harvested yet');

    await store.setProgress(1, Progress.finished);
    expect(store.justHarvested, 1, reason: 'the transition into finished fires');
  });

  test('the signal is one-shot: consumed, then null', () async {
    await store.upsert(owned(1, 'Hades'));
    await store.setProgress(1, Progress.finished);

    expect(store.consumeJustHarvested(), 1);
    expect(store.justHarvested, isNull, reason: 'consuming clears it');
    expect(store.consumeJustHarvested(), isNull, reason: 'and stays clear');
  });

  test('re-finishing an already-finished game does NOT re-fire', () async {
    await store.upsert(owned(1, 'Hades', progress: Progress.finished));
    // It was already finished when loaded, so setting finished again is not a
    // transition and must not trigger a burst.
    await store.setProgress(1, Progress.finished);
    expect(store.justHarvested, isNull,
        reason: 'the burst is the transition, not the state');
  });

  test('moving AWAY from finished does not fire', () async {
    await store.upsert(owned(1, 'Hades', progress: Progress.finished));
    await store.setProgress(1, Progress.playing);
    expect(store.justHarvested, isNull);
  });

  test('the first harvest is a level-up (level 1 -> 2)', () async {
    // levelFor(0).level == 1, levelFor(1).level == 2, so the very first harvest
    // crosses a threshold.
    expect(levelFor(0).level, 1);
    expect(levelFor(1).level, 2);

    await store.upsert(owned(1, 'Hades'));
    await store.setProgress(1, Progress.finished);
    expect(store.justHarvested, 1);
    expect(store.harvestLevelledUp, isTrue,
        reason: 'first finished game reaches level 2');
  });

  test('a harvest that does not cross a threshold is not a level-up', () async {
    // Thresholds: reach L2 at 1, L3 at 3. So the SECOND harvest (count 1 -> 2)
    // stays inside level 2 and is not a level-up.
    await store.upsert(owned(1, 'A', progress: Progress.finished));
    await store.upsert(owned(2, 'B'));
    await store.load();

    await store.setProgress(2, Progress.finished);
    expect(store.justHarvested, 2);
    expect(store.harvestLevelledUp, isFalse,
        reason: 'count 1 -> 2 stays in level 2');
  });

  test('consuming clears the level-up flag too', () async {
    await store.upsert(owned(1, 'Hades'));
    await store.setProgress(1, Progress.finished);
    expect(store.harvestLevelledUp, isTrue);
    store.consumeJustHarvested();
    expect(store.harvestLevelledUp, isFalse);
  });
}
