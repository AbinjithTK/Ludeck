// Stage 3 draw-line creation animation is driven by a real store event, not a
// demo trigger. These lock the justAdded contract: it fires when a genuinely
// NEW game is inserted, it is one-shot (consumed, never replays), and it does
// NOT fire when re-adding a game already in the collection (no line to draw).
// Plain test() -- no widget, no FakeAsync (see CONSTRAINTS.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
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

  TreeItem game(int id, String title) => TreeItem(
        game: Game(igdbId: id, title: title),
        entry: Entry(igdbId: id, ownership: Ownership.owned, progress: Progress.untouched),
        copies: const [],
      );

  test('adding a new game flags it as just added', () async {
    expect(store.justAdded, isNull, reason: 'nothing added yet');
    await store.upsert(game(1, 'Hollow Knight'));
    expect(store.justAdded, 1, reason: 'a genuinely new game fires justAdded');
  });

  test('the signal is one-shot: consumed, then null', () async {
    await store.upsert(game(1, 'Hollow Knight'));
    expect(store.consumeJustAdded(), 1);
    expect(store.justAdded, isNull, reason: 'consuming clears it');
    expect(store.consumeJustAdded(), isNull, reason: 'and stays clear');
  });

  test('re-adding an existing game does NOT fire (no line to draw)', () async {
    await store.upsert(game(1, 'Hollow Knight'));
    store.consumeJustAdded();
    // The repo upsert leaves an existing entry untouched; re-adding must not
    // animate a node that is already on the roadmap.
    await store.upsert(game(1, 'Hollow Knight'));
    expect(store.justAdded, isNull,
        reason: 'the node already exists, so nothing draws');
  });

  test('a second distinct game fires for its own id', () async {
    await store.upsert(game(1, 'Hollow Knight'));
    store.consumeJustAdded();
    await store.upsert(game(2, 'Celeste'));
    expect(store.justAdded, 2);
  });

  test('addShared fires justAdded for a new game', () async {
    await store.addShared(
      game(3, 'Outer Wilds'),
      Source(
        igdbId: 3,
        kind: SourceKind.youtube,
        matchMethod: MatchMethod.exact,
        addedAt: DateTime(2026),
      ),
    );
    expect(store.justAdded, 3);
  });
}
