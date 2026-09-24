import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/pick.dart';

void main() {
  TreeItem item(
    int id,
    String title, {
    Ownership ownership = Ownership.owned,
    Progress progress = Progress.untouched,
    int? seconds,
    bool shelved = false,
    List<Platform> platforms = const [],
  }) =>
      TreeItem(
        game: Game(igdbId: id, title: title, timeToBeatSeconds: seconds),
        entry: Entry(
          igdbId: id,
          ownership: ownership,
          progress: progress,
          shelved: shelved,
        ),
        copies: platforms
            .map((p) => Copy(
                  igdbId: id,
                  platform: p,
                  form: Form.digital,
                  acquired: Acquired.bought,
                ))
            .toList(),
      );

  group('nothing survives', () {
    test('an empty collection returns null', () {
      expect(choosePick([]), isNull);
    });

    test('only seeds returns null, because a seed is not owned', () {
      final items = [item(1, 'Pentiment', ownership: Ownership.spotted)];
      expect(choosePick(items), isNull);
    });

    test('everything finished or abandoned returns null', () {
      final items = [
        item(1, 'A', progress: Progress.finished),
        item(2, 'B', progress: Progress.abandoned),
      ];
      expect(choosePick(items), isNull);
    });

    test('a shelved game is never picked even if otherwise eligible', () {
      final items = [item(1, 'A', shelved: true)];
      expect(choosePick(items), isNull);
    });

    test('a device filter that matches nothing returns null', () {
      final items = [item(1, 'A', platforms: [Platform.pc])];
      expect(choosePick(items, devices: {Platform.switch_}), isNull);
    });

    test('an hours filter nothing known fits returns null', () {
      final items = [item(1, 'A', seconds: 360000)]; // 100h
      expect(choosePick(items, hoursFree: 2), isNull);
    });
  });

  group('continuation beats everything else', () {
    test('playing beats installed beats untouched, regardless of length', () {
      final items = [
        item(1, 'Untouched', progress: Progress.untouched, seconds: 3600),
        item(2, 'Installed', progress: Progress.installed, seconds: 360000),
        item(3, 'Playing', progress: Progress.playing, seconds: 360000),
      ];
      expect(choosePick(items)!.item.game.title, 'Playing');
    });

    test('installed beats untouched even when untouched is much shorter', () {
      final items = [
        item(1, 'Untouched', progress: Progress.untouched, seconds: 1800),
        item(2, 'Installed', progress: Progress.installed, seconds: 360000),
      ];
      expect(choosePick(items)!.item.game.title, 'Installed');
    });
  });

  group('among equal continuation, shortest known length wins', () {
    test('a shorter untouched game beats a longer untouched game', () {
      final items = [
        item(1, 'Long', seconds: 360000),
        item(2, 'Short', seconds: 3600),
      ];
      expect(choosePick(items)!.item.game.title, 'Short');
    });

    test('unknown length sorts after every known length', () {
      final items = [
        item(1, 'Unknown', seconds: null),
        item(2, 'Long but known', seconds: 360000),
      ];
      expect(choosePick(items)!.item.game.title, 'Long but known',
          reason: 'a known length, however long, is preferred over a guess');
    });
  });

  group('unknown length is kept, not dropped, under an hours filter', () {
    test('an item with no recorded length survives an hoursFree filter', () {
      final items = [item(1, 'Unknown', seconds: null)];
      expect(choosePick(items, hoursFree: 1), isNotNull,
          reason: 'unknown is not evidence of being too long');
    });

    test('a known-too-long item is dropped while unknown is kept', () {
      final items = [
        item(1, 'Too long', seconds: 360000),
        item(2, 'Unknown', seconds: null),
      ];
      expect(choosePick(items, hoursFree: 1)!.item.game.title, 'Unknown');
    });

    test('a known-short item beats unknown once both survive the filter', () {
      final items = [
        item(1, 'Unknown', seconds: null),
        item(2, 'Known short', seconds: 3600),
      ];
      expect(choosePick(items, hoursFree: 2)!.item.game.title, 'Known short');
    });
  });

  group('device filter', () {
    test('a game on the requested device is kept', () {
      final items = [item(1, 'A', platforms: [Platform.pc])];
      expect(choosePick(items, devices: {Platform.pc}), isNotNull);
    });

    test('a game owned on two platforms matches on either', () {
      final items = [
        item(1, 'A', platforms: [Platform.pc, Platform.switch_])
      ];
      expect(choosePick(items, devices: {Platform.switch_}), isNotNull);
    });

    test('an empty device set applies no filter at all', () {
      final items = [item(1, 'A', platforms: [Platform.pc])];
      expect(choosePick(items, devices: const {}), isNotNull);
    });
  });

  group('the reason is true of the item actually chosen', () {
    test('a playing game states it is already in hand', () {
      final items = [item(1, 'A', progress: Progress.playing, seconds: 32400)];
      expect(choosePick(items)!.reason, contains('Already in hand'));
    });

    test('an untouched game within the time budget names the fit', () {
      final items = [item(1, 'A', seconds: 3600)];
      expect(choosePick(items, hoursFree: 3)!.reason,
          contains('Short enough for tonight'));
    });

    test('a reason never claims a length the item does not have', () {
      final items = [item(1, 'A', seconds: null)];
      final pick = choosePick(items)!;
      expect(pick.reason, isNot(contains('hour')),
          reason: 'no length is known, so none may be stated');
    });
  });
}
