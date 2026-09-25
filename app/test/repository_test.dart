import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';

/// These tests assert the rules in docs/DECISIONS.md, not the implementation.
/// If the storage engine changes again they should all still pass unchanged.
void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  TreeItem item(
    int id,
    String title, {
    Ownership ownership = Ownership.owned,
    Progress progress = Progress.untouched,
    int? seconds,
    List<Copy> copies = const [],
  }) =>
      TreeItem(
        game: Game(igdbId: id, title: title, timeToBeatSeconds: seconds),
        entry: Entry(igdbId: id, ownership: ownership, progress: progress),
        copies: copies,
      );

  Copy copy(int id, Platform p,
          [Form f = Form.digital, Acquired a = Acquired.bought]) =>
      Copy(igdbId: id, platform: p, form: f, acquired: a);

  group('the two axes stay independent', () {
    test('selling a game does not erase that it was finished', () async {
      await repo.upsert(item(1, 'Hades',
          progress: Progress.finished, copies: [copy(1, Platform.pc)]));

      // The sale: the copy goes, the record stays.
      await repo.removeCopy(1, Platform.pc, Form.digital);
      await repo.setOwnership(1, Ownership.released);

      final loaded = (await repo.load()).single;
      expect(loaded.entry.ownership, Ownership.released);
      expect(loaded.entry.progress, Progress.finished,
          reason: 'a sale must never touch progress');
      expect(loaded.copies, isEmpty);
      expect(loaded.isHarvested, isTrue);
    });

    test('setting ownership leaves progress alone', () async {
      await repo.upsert(item(2, 'Celeste', progress: Progress.playing));
      await repo.setOwnership(2, Ownership.released);
      expect((await repo.load()).single.entry.progress, Progress.playing);
    });

    test('setting progress leaves ownership alone', () async {
      await repo.upsert(item(3, 'Tunic', ownership: Ownership.spotted));
      await repo.setProgress(3, Progress.finished);
      expect((await repo.load()).single.entry.ownership, Ownership.spotted);
    });
  });

  group('ownership is a set of copies', () {
    test('one game on two platforms keeps two copies', () async {
      await repo.upsert(item(4, 'Hollow Knight', copies: [
        copy(4, Platform.pc),
        copy(4, Platform.switch_),
      ]));
      final loaded = (await repo.load()).single;
      expect(loaded.copies, hasLength(2));
      expect(loaded.platforms, {Platform.pc, Platform.switch_});
    });

    test('selling one platform leaves the other', () async {
      await repo.upsert(item(5, 'Hollow Knight', copies: [
        copy(5, Platform.pc),
        copy(5, Platform.switch_),
      ]));
      await repo.removeCopy(5, Platform.pc, Form.digital);
      expect((await repo.load()).single.platforms, {Platform.switch_});
    });

    test('a physical and a digital copy of one game both survive', () async {
      await repo.upsert(item(6, 'Celeste', copies: [
        copy(6, Platform.switch_, Form.digital),
        copy(6, Platform.switch_, Form.physical),
      ]));
      expect((await repo.load()).single.copies, hasLength(2));
    });

    test('re-importing does not duplicate an identical copy', () async {
      final same = item(7, 'Hades', copies: [copy(7, Platform.pc)]);
      await repo.upsert(same);
      await repo.upsert(same);
      expect((await repo.load()).single.copies, hasLength(1));
    });
  });

  group('persistence uses the enum name', () {
    test('every status value round-trips', () async {
      var id = 100;
      for (final o in Ownership.values) {
        for (final pr in Progress.values) {
          await repo.upsert(
              item(id, 'g$id', ownership: o, progress: pr));
          id++;
        }
      }
      final loaded = await repo.load();
      expect(loaded, hasLength(Ownership.values.length * Progress.values.length));
      for (final t in loaded) {
        expect(Ownership.values, contains(t.entry.ownership));
        expect(Progress.values, contains(t.entry.progress));
      }
    });

    test('switch_ survives its trailing underscore', () async {
      await repo.upsert(
          item(8, 'Metroid', copies: [copy(8, Platform.switch_)]));
      expect((await repo.load()).single.copies.single.platform,
          Platform.switch_);
    });

    test('every platform, form and acquisition value round-trips', () async {
      var id = 200;
      for (final pl in Platform.values) {
        for (final f in Form.values) {
          for (final a in Acquired.values) {
            await repo.upsert(
                item(id, 'g$id', copies: [copy(id, pl, f, a)]));
            id++;
          }
        }
      }
      final loaded = await repo.load();
      for (final t in loaded) {
        expect(t.copies, hasLength(1));
      }
    });
  });

  group('shelved replaces delete', () {
    test('a shelved game disappears from the collection but is not gone',
        () async {
      await repo.upsert(item(9, 'Disco Elysium'));
      expect(await repo.load(), hasLength(1));

      await repo.shelve(9);
      expect(await repo.load(), isEmpty, reason: 'hidden from the collection');
      expect(await repo.gameCount(), 1, reason: 'but the row still exists');
    });
  });

  group('completion is the signal', () {
    test('a finished game reads as harvested after a round trip', () async {
      await repo.upsert(item(10, 'Celeste', seconds: 28800));
      await repo.setProgress(10, Progress.finished);
      expect((await repo.load()).single.isHarvested, isTrue);
    });

    test('an unstarted game is not harvested however short it is', () async {
      await repo.upsert(item(11, 'Celeste', seconds: 28800)); // 8 hours
      expect((await repo.load()).single.isHarvested, isFalse,
          reason: 'length is not an achievement');
    });

    test('setting a game aside is not the same event as finishing it', () async {
      await repo.upsert(item(12, 'Tunic', seconds: 28800));
      await repo.setProgress(12, Progress.abandoned);
      expect((await repo.load()).single.isHarvested, isFalse);
    });

    test('hours still round-trip, because the pick depends on them', () async {
      await repo.upsert(item(13, 'Disco Elysium', seconds: 118800));
      expect((await repo.load()).single.game.hours, 33,
          reason: 'seconds to hours, divided exactly once');
    });

    test('a game with no recorded length keeps null hours, not a guess',
        () async {
      await repo.upsert(item(16, 'Unknown'));
      expect((await repo.load()).single.game.hours, isNull);
    });
  });

  group('branches are the user\'s own', () {
    test('a captured game with no placement is unplaced', () async {
      await repo.upsert(item(14, 'Pentiment'));
      expect(await repo.unplacedGameIds(), [14]);
    });

    test('placing a game on a branch removes it from unplaced', () async {
      await repo.upsert(item(15, 'Blue Prince'));
      final branch = await repo.createBranch('Short and sweet');
      await repo.place(15, branch);
      expect(await repo.unplacedGameIds(), isEmpty);
    });

    test('one game can hang on two branches', () async {
      await repo.upsert(item(16, 'Hollow Knight'));
      final a = await repo.createBranch('Metroidvanias');
      final b = await repo.createBranch('Finish this year');
      await repo.place(16, a);
      await repo.place(16, b);
      expect(await repo.unplacedGameIds(), isEmpty);
      expect(await repo.branches(), hasLength(2));
    });

    test('branches come back in sort order', () async {
      await repo.createBranch('third', sortOrder: 3);
      await repo.createBranch('first', sortOrder: 1);
      await repo.createBranch('second', sortOrder: 2);
      expect((await repo.branches()).map((b) => b.name).toList(),
          ['first', 'second', 'third']);
    });

    test('a branch can be renamed, because the user named it', () async {
      final id = await repo.createBranch('Wrong name');
      await repo.renameBranch(id, 'Right name');
      expect((await repo.branches()).single.name, 'Right name');
    });
  });

  group('seeding', () {
    test('an empty database gets the fixture, and only once', () async {
      await repo.seedIfEmpty();
      final first = await repo.load();
      expect(first, isNotEmpty);

      await repo.seedIfEmpty();
      expect((await repo.load()).length, first.length);
    });

    test('seeding does not run when there is real data', () async {
      await repo.upsert(item(17, 'Only this'));
      await repo.seedIfEmpty();
      expect((await repo.load()).single.game.title, 'Only this');
    });
  });

  group('setCoverUrl', () {
    // The lazy cover-art fill-in: a game that shipped with no cover (the
    // bundled catalogue carries none by design) gets one written in after the
    // fact by a background lookup, and this is the one place that write lands.

    test('fills in a cover for a game that had none', () async {
      await repo.upsert(item(20, 'Hollow Knight'));
      expect((await repo.load()).single.game.coverUrl, isNull);

      await repo.setCoverUrl(20, 'https://example.com/hk.png');

      expect((await repo.load()).single.game.coverUrl,
          'https://example.com/hk.png');
    });

    test('touches nothing else on the row', () async {
      await repo.upsert(item(21, 'Celeste',
          progress: Progress.finished, seconds: 28800));
      await repo.setRating(21, 5);

      await repo.setCoverUrl(21, 'https://example.com/celeste.png');

      final reread = (await repo.load()).single;
      expect(reread.game.title, 'Celeste');
      expect(reread.game.hours, 8);
      expect(reread.entry.progress, Progress.finished);
      expect(reread.entry.rating, 5);
    });
  });
}
