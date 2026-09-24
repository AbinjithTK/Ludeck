import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/db/database.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:sqflite/sqflite.dart';

/// Tests for the things that go wrong in production rather than in a demo:
/// re-imports, corrupt rows, hostile input, and half-finished writes.
///
/// These exist because an audit of the repository found two real defects that no
/// feature test would ever have caught, and a test is the only thing that stops
/// either from coming back.
void main() {
  setUpAll(initDatabasePlatform);

  late Repository repo;
  late Database raw;

  setUp(() async {
    raw = await openInMemoryDatabase();
    repo = Repository(raw);
  });

  tearDown(() async => repo.close());

  TreeItem item(
    int id,
    String title, {
    int? seconds,
    Ownership ownership = Ownership.owned,
    Progress progress = Progress.untouched,
    int? rating,
    List<Copy> copies = const [],
  }) =>
      TreeItem(
        game: Game(igdbId: id, title: title, timeToBeatSeconds: seconds),
        entry: Entry(
          igdbId: id,
          ownership: ownership,
          progress: progress,
          rating: rating,
        ),
        copies: copies,
      );

  group('a re-import must never destroy what the user recorded', () {
    test('re-importing a finished, rated game keeps the rating and the status',
        () async {
      await repo.upsert(item(1, 'Hades'));
      await repo.setProgress(1, Progress.finished);
      await repo.setRating(1, 5);

      // The same game arrives again, as a fresh capture with default state.
      // This is the shape an import, a share-sheet add, or a future Steam sync
      // takes, and it used to silently overwrite the entry row.
      await repo.upsert(item(1, 'Hades'));

      final e = (await repo.load()).single.entry;
      expect(e.progress, Progress.finished,
          reason: 'a re-import is not the user un-finishing a game');
      expect(e.rating, 5, reason: 'nor is it them withdrawing a rating');
    });

    test('a re-import still refreshes catalogue data, which IGDB owns', () async {
      await repo.upsert(item(2, 'Old Title', seconds: 3600));
      await repo.upsert(item(2, 'Corrected Title', seconds: 7200));

      final g = (await repo.load()).single.game;
      expect(g.title, 'Corrected Title');
      expect(g.hours, 2, reason: 'length is catalogue data and may be corrected');
    });

    test('a re-import does not resurrect a shelved game', () async {
      await repo.upsert(item(3, 'Set aside'));
      await repo.shelve(3);
      await repo.upsert(item(3, 'Set aside'));

      expect(await repo.load(), isEmpty,
          reason: 'shelving is the user\'s decision and an import cannot undo it');
    });

    test('a re-import keeps every platform the game is owned on', () async {
      await repo.upsert(item(20, 'Hollow Knight', copies: [
        const Copy(
            igdbId: 20,
            platform: Platform.pc,
            form: Form.digital,
            acquired: Acquired.bought),
        const Copy(
            igdbId: 20,
            platform: Platform.switch_,
            form: Form.physical,
            acquired: Acquired.gift),
      ]));
      expect((await repo.load()).single.copies, hasLength(2));

      // The same game arrives again carrying no copies, which is what a search
      // result or a shared link looks like.
      await repo.upsert(item(20, 'Hollow Knight'));

      expect((await repo.load()).single.copies, hasLength(2),
          reason: 'an import that knows nothing about your shelf must not '
              'conclude your shelf is empty');
    });

    test('a re-import keeps the branch the game was placed on', () async {
      await repo.upsert(item(21, 'Celeste'));
      final branch = await repo.createBranch('Short and sweet');
      await repo.place(21, branch);
      expect(await repo.unplacedGameIds(), isEmpty);

      await repo.upsert(item(21, 'Celeste'));

      expect(await repo.unplacedGameIds(), isEmpty,
          reason: 'where a fruit hangs is the user\'s arrangement, not '
              'catalogue data');
    });

    test('a re-import keeps the note and who recommended it', () async {
      await repo.upsert(TreeItem(
        game: const Game(igdbId: 22, title: 'Pentiment'),
        entry: const Entry(
          igdbId: 22,
          ownership: Ownership.spotted,
          progress: Progress.untouched,
          note: 'Priya said start here',
          recommendedBy: 'Priya',
        ),
        copies: const [],
      ));

      await repo.upsert(item(22, 'Pentiment'));

      final e = (await repo.load()).single.entry;
      expect(e.note, 'Priya said start here');
      expect(e.recommendedBy, 'Priya',
          reason: 'a seed carries its source, which is the whole premise');
    });
  });

  group('one bad row stays one bad row', () {
    test('an unknown status value skips that game, not the whole collection',
        () async {
      await repo.upsert(item(4, 'Good One'));
      await repo.upsert(item(5, 'Bad One'));

      // Corrupt exactly one row, the way a hand-edited file or a downgrade
      // would. Written through the raw handle because the repository correctly
      // refuses to produce this.
      await raw.update('entries', {'progress': 'wantToPlay'},
          where: 'igdb_id = ?', whereArgs: [5]);

      final result = await repo.loadDetailed();
      expect(result.items, hasLength(1),
          reason: 'the readable game must still be readable');
      expect(result.items.single.game.title, 'Good One');
      expect(result.skipped, 1, reason: 'and the loss must be reported, not hidden');
    });

    test('a corrupt copy loses the copy, not the game it belongs to', () async {
      await repo.upsert(item(6, 'Two Platforms', copies: [
        const Copy(
            igdbId: 6,
            platform: Platform.pc,
            form: Form.digital,
            acquired: Acquired.bought),
      ]));
      await raw.update('copies', {'platform': 'dreamcast'},
          where: 'igdb_id = ?', whereArgs: [6]);

      final result = await repo.loadDetailed();
      expect(result.items, hasLength(1), reason: 'the game survives');
      expect(result.items.single.copies, isEmpty);
      expect(result.skipped, 1);
    });

    test('a rating outside 1 to 5 in the file reads as no rating', () async {
      await repo.upsert(item(7, 'Edited By Hand'));
      await raw.update('entries', {'rating': 9},
          where: 'igdb_id = ?', whereArgs: [7]);

      final loaded = (await repo.load()).single;
      expect(loaded.entry.rating, isNull,
          reason: 'a nine star game is worse than an unrated one');
    });

    test('an empty database is a clean empty result, not a failure', () async {
      final result = await repo.loadDetailed();
      expect(result.items, isEmpty);
      expect(result.skipped, 0);
    });
  });

  group('input that should be refused is refused', () {
    test('a rating of 0 or 6 throws rather than being clamped', () async {
      await repo.upsert(item(8, 'Celeste'));
      expect(() => repo.setRating(8, 0), throwsArgumentError);
      expect(() => repo.setRating(8, 6), throwsArgumentError);
      expect(() => repo.setRating(8, -1), throwsArgumentError);
    });

    test('clearing a rating is allowed, because unrating is a real action',
        () async {
      await repo.upsert(item(9, 'Tunic'));
      await repo.setRating(9, 4);
      await repo.setRating(9, null);
      expect((await repo.load()).single.entry.rating, isNull);
    });

    test('a blank or whitespace branch name is refused', () {
      expect(() => repo.createBranch(''), throwsArgumentError);
      expect(() => repo.createBranch('   '), throwsArgumentError);
      expect(() => repo.createBranch('\t\n'), throwsArgumentError);
    });

    test('a branch name is trimmed rather than stored with its padding',
        () async {
      final id = await repo.createBranch('  Short and sweet  ');
      final b = (await repo.branches()).firstWhere((x) => x.id == id);
      expect(b.name, 'Short and sweet');
    });

    test('an unbounded paste is refused at both entry points', () async {
      final huge = 'x' * (Repository.maxNameLength + 1);
      expect(() => repo.createBranch(huge), throwsArgumentError);
      final id = await repo.createBranch('Fine');
      expect(() => repo.renameBranch(id, huge), throwsArgumentError);
      expect(() => repo.upsert(item(10, huge)), throwsArgumentError);
    });

    test('a blank game title is refused', () {
      expect(() => repo.upsert(item(11, '   ')), throwsArgumentError);
    });

    test('a name at exactly the limit is accepted, so the bound is inclusive',
        () async {
      final exact = 'x' * Repository.maxNameLength;
      final id = await repo.createBranch(exact);
      expect(id, greaterThan(0));
    });
  });

  group('deleting a branch keeps the games', () {
    test('the placements go and every game stays', () async {
      await repo.upsert(item(12, 'Hollow Knight'));
      await repo.upsert(item(13, 'Celeste'));
      final branch = await repo.createBranch('Metroidvanias');
      await repo.place(12, branch);
      await repo.place(13, branch);

      await repo.deleteBranch(branch);

      expect(await repo.branches(), isEmpty);
      expect(await repo.load(), hasLength(2),
          reason: 'a container is not its contents');
      expect(await repo.unplacedGameIds(), containsAll([12, 13]),
          reason: 'and they land back in the ordinary unplaced state');
    });

    test('deleting a branch that does not exist is not an error', () async {
      await repo.deleteBranch(999);
      expect(await repo.branches(), isEmpty);
    });
  });

  group('reordering branches is all or nothing', () {
    test('every branch ends up with a distinct position', () async {
      final a = await repo.createBranch('A');
      final b = await repo.createBranch('B');
      final c = await repo.createBranch('C');

      await repo.reorderBranches([c, a, b]);

      final order = (await repo.branches()).map((x) => x.id).toList();
      expect(order, [c, a, b]);
      final positions = (await repo.branches()).map((x) => x.sortOrder).toSet();
      expect(positions, hasLength(3), reason: 'no two branches share a slot');
    });

    test('an empty reorder changes nothing rather than wiping the order',
        () async {
      final a = await repo.createBranch('A');
      await repo.reorderBranches([]);
      expect((await repo.branches()).single.id, a);
    });
  });

  group('shelving is reversible, or the word is a lie', () {
    test('a shelved game can be brought back with everything intact', () async {
      await repo.upsert(item(14, 'Disco Elysium'));
      await repo.setProgress(14, Progress.finished);
      await repo.setRating(14, 4);
      await repo.shelve(14);
      expect(await repo.load(), isEmpty);

      await repo.unshelve(14);
      final back = (await repo.load()).single;
      expect(back.entry.progress, Progress.finished);
      expect(back.entry.rating, 4);
    });
  });
}
