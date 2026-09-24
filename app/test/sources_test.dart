// Stage 1 of the share-to-library feature: source storage.
//
// The migration test is the important one here. `_onUpgrade` used to throw
// outright, so every existing install would have crashed on first open after
// the version bump. That failure mode only shows up on an UPGRADE path, never
// on a fresh install, which is why it gets a real on-disk database.

// dart:io also exports `Platform`, which is one of our own enums, and this file
// imports both. Prefixed for the same reason database.dart prefixes it.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/db/database.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The v1 schema, as it shipped. Deliberately a verbatim copy rather than an
/// import: this is what is already on a user's phone, and it must not change
/// when the current DDL changes.
const List<String> _v1Ddl = [
  '''
  CREATE TABLE games (
    igdb_id              INTEGER PRIMARY KEY,
    title                TEXT    NOT NULL,
    cover_url            TEXT,
    release_year         INTEGER,
    time_to_beat_seconds INTEGER
  )
  ''',
  '''
  CREATE TABLE entries (
    igdb_id        INTEGER PRIMARY KEY REFERENCES games(igdb_id) ON DELETE CASCADE,
    ownership      TEXT    NOT NULL,
    progress       TEXT    NOT NULL,
    rating         INTEGER,
    note           TEXT,
    last_played_at INTEGER,
    recommended_by TEXT,
    shelved        INTEGER NOT NULL DEFAULT 0
  )
  ''',
];

void main() {
  setUpAll(initDatabasePlatform);

  group('schema migration', () {
    late io.Directory dir;
    late String path;

    setUp(() async {
      dir = await io.Directory.systemTemp.createTemp('ludeck_migration_');
      path = p.join(dir.path, 'ludeck.db');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('a v1 database upgrades to v2 without losing the collection',
        () async {
      // Stand up a database exactly as version 1 left it.
      final old = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          for (final statement in _v1Ddl) {
            await db.execute(statement);
          }
        },
      );
      await old.insert('games', {'igdb_id': 1020, 'title': 'Hollow Knight'});
      await old.insert('entries', {
        'igdb_id': 1020,
        'ownership': Ownership.owned.name,
        'progress': Progress.playing.name,
        'rating': 9,
        'recommended_by': 'Priya',
      });
      await old.close();

      // Reopen through the shipping opener, which runs the real migration.
      final db = await openLudeckDatabaseAt(path);
      addTearDown(db.close);

      expect(await db.getVersion(), kSchemaVersion);

      // The collection survived. This is the whole point: a migration that
      // recreated the tables would pass a "sources exists" check and still
      // have destroyed the user's data.
      final entries = await db.query('entries');
      expect(entries, hasLength(1));
      expect(entries.single['rating'], 9);
      expect(entries.single['recommended_by'], 'Priya');

      // And the new table is usable, not merely present.
      await db.insert('sources', {
        'igdb_id': 1020,
        'url': 'https://www.twitch.tv/x/clip/abc',
        'kind': SourceKind.twitch.name,
        'match_method': MatchMethod.exact.name,
        'added_at': 1,
      });
      expect(await db.query('sources'), hasLength(1));
    });

    test('every schema version has a migration registered', () async {
      // The mistake this catches: someone bumps kSchemaVersion and forgets the
      // _migrations entry. A fresh install still works, so it passes review,
      // and then every existing install throws on first open.
      //
      // Version 1 has no migration by definition; it is the create path.
      for (var version = 2; version <= kSchemaVersion; version++) {
        expect(
          kMigrationVersions,
          contains(version),
          reason: 'schema v$version has no migration step in database.dart',
        );
      }
    });
  });

  group('sources', () {
    late Repository repo;

    setUp(() async {
      repo = await Repository.openInMemory();
      await repo.upsert(TreeItem(
        game: const Game(igdbId: 1020, title: 'Hollow Knight'),
        entry: const Entry(
          igdbId: 1020,
          ownership: Ownership.spotted,
          progress: Progress.untouched,
        ),
        copies: const [],
      ));
    });

    tearDown(() async => repo.close());

    Source src({
      String? url,
      SourceKind kind = SourceKind.youtube,
      MatchMethod method = MatchMethod.metadata,
      String? channel,
      int at = 1000,
    }) =>
        Source(
          igdbId: 1020,
          url: url,
          kind: kind,
          matchMethod: method,
          channel: channel,
          addedAt: DateTime.fromMillisecondsSinceEpoch(at),
        );

    test('round-trips every field', () async {
      await repo.addSource(Source(
        igdbId: 1020,
        url: 'https://youtu.be/abc',
        kind: SourceKind.youtube,
        matchMethod: MatchMethod.metadata,
        title: 'Hollow Knight is a masterpiece',
        channel: 'SomeCritic',
        thumbUrl: 'https://img.example/abc.jpg',
        addedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ));

      final got = (await repo.sourcesFor(1020)).single;
      expect(got.id, isNotNull);
      expect(got.url, 'https://youtu.be/abc');
      expect(got.kind, SourceKind.youtube);
      expect(got.matchMethod, MatchMethod.metadata);
      expect(got.title, 'Hollow Knight is a masterpiece');
      expect(got.channel, 'SomeCritic');
      expect(got.thumbUrl, 'https://img.example/abc.jpg');
      expect(got.addedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('re-sharing the same link does not duplicate it', () async {
      await repo.addSource(src(url: 'https://youtu.be/abc'));
      await repo.addSource(src(url: 'https://youtu.be/abc', at: 2000));

      expect(await repo.sourcesFor(1020), hasLength(1));
    });

    test('two link-less shares are two sources, not one', () async {
      // A friend texting "play Hollow Knight" and a second friend texting the
      // same thing are two separate facts. SQLite treats NULLs as distinct in
      // a UNIQUE constraint, which is what makes this work.
      await repo.addSource(
          src(kind: SourceKind.text, method: MatchMethod.text, channel: 'Ravi'));
      await repo.addSource(src(
          kind: SourceKind.text,
          method: MatchMethod.text,
          channel: 'Meera',
          at: 2000));

      final all = await repo.sourcesFor(1020);
      expect(all, hasLength(2));
      expect(all.map((s) => s.channel), containsAll(['Ravi', 'Meera']));
    });

    test('newest first', () async {
      await repo.addSource(src(url: 'https://a.example', at: 1000));
      await repo.addSource(src(url: 'https://b.example', at: 3000));
      await repo.addSource(src(url: 'https://c.example', at: 2000));

      expect(
        (await repo.sourcesFor(1020)).map((s) => s.url),
        ['https://b.example', 'https://c.example', 'https://a.example'],
      );
    });

    test('removing one leaves the others', () async {
      await repo.addSource(src(url: 'https://a.example'));
      await repo.addSource(src(url: 'https://b.example', at: 2000));

      final first = (await repo.sourcesFor(1020)).last;
      await repo.removeSource(first.id!);

      final left = await repo.sourcesFor(1020);
      expect(left, hasLength(1));
      expect(left.single.url, 'https://b.example');
    });

    test('a second import of the same game keeps its sources', () async {
      // The bug this guards is the one already fixed in `upsert`: a re-import
      // must not cascade-delete rows hanging off the game.
      await repo.addSource(src(url: 'https://youtu.be/abc'));

      await repo.upsert(TreeItem(
        game: const Game(igdbId: 1020, title: 'Hollow Knight', releaseYear: 2017),
        entry: const Entry(
          igdbId: 1020,
          ownership: Ownership.owned,
          progress: Progress.playing,
        ),
        copies: const [],
      ));

      expect(await repo.sourcesFor(1020), hasLength(1));
    });

    test('sources for an unknown game are empty, not an error', () async {
      expect(await repo.sourcesFor(999999), isEmpty);
    });
  });
}
