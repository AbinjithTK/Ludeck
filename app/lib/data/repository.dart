import 'package:sqflite/sqflite.dart';

import 'db/database.dart';
import 'enums.dart';
import 'models.dart';

/// The outcome of a read, including what could not be read.
///
/// `skipped` exists because of a dead state that had no exit. Enum parsing uses
/// `byName`, which throws on a value this build does not recognise. That throw
/// used to escape `load()`, so ONE unreadable row out of a thousand produced a
/// completely empty screen with no explanation and no way back. A corrupt row is
/// a row-sized problem and it must stay that size.
class LoadResult {
  const LoadResult({required this.items, required this.skipped});

  final List<TreeItem> items;

  /// How many rows could not be read. Anything above zero should be surfaced to
  /// the user, quietly but honestly. Never silently swallow it: a row that
  /// vanishes without a word is how someone concludes the app lost their data.
  final int skipped;
}

/// The only thing that talks to the database.
///
/// Nothing above this file writes SQL, and nothing below it knows what a
/// TreeItem is. That boundary is what lets the storage engine change without
/// touching the tree, which already happened once when code generation turned
/// out to be unavailable on this toolchain.
class Repository {
  Repository(this._db);

  final Database _db;

  /// Longest accepted branch name or game title.
  ///
  /// Unbounded text straight into SQLite is a real problem on a phone, not a
  /// theoretical one: nothing in the UI can lay out a 10,000 character branch
  /// name, and nothing stops a paste from producing one.
  static const int maxNameLength = 120;

  // ---------------------------------------------------------------------------
  // Integrity. Read-only, and worth having for a reason that is easy to miss.
  // ---------------------------------------------------------------------------

  /// Whether foreign keys are enforced on THIS connection.
  ///
  /// SQLite defaults them OFF and the setting is per-connection, not stored in
  /// the file. `database.dart` turns them on in `onConfigure`, and every
  /// `ON DELETE CASCADE` in the schema is decoration if that line is ever
  /// removed. Nothing would fail loudly: writes would keep working and orphan
  /// rows would accumulate silently. So it is asserted rather than assumed.
  Future<bool> foreignKeysEnforced() async {
    final rows = await _db.rawQuery('PRAGMA foreign_keys');
    if (rows.isEmpty) return false;
    final value = rows.first.values.first;
    return value == 1 || value == '1';
  }

  /// Rows that point at a parent which does not exist.
  ///
  /// `PRAGMA foreign_key_check` finds violations that enforcement would have
  /// prevented, which is exactly the case that matters here: enforcement is
  /// per-connection, so a database written by a build BEFORE `onConfigure`
  /// existed can already contain orphans, and turning the pragma on later does
  /// not retroactively clean them. Cheap on a collection this size.
  ///
  /// Returns one description per violating row, empty when the database is
  /// consistent.
  Future<List<String>> foreignKeyViolations() async {
    final rows = await _db.rawQuery('PRAGMA foreign_key_check');
    return rows
        .map((r) => '${r['table']} rowid=${r['rowid']} -> ${r['parent']}')
        .toList();
  }

  /// Every table the schema declares, as SQLite actually holds it.
  ///
  /// Used by the audit test to notice a table added to the DDL without a
  /// corresponding cascade decision, rather than discovering it when a delete
  /// leaves rows behind.
  Future<Set<String>> tableNames() async {
    final rows = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  /// The foreign keys SQLite reports for one table, as (column, parent, onDelete).
  ///
  /// Reads the engine rather than the DDL string, so a clause that was written
  /// but not applied -- a migration that created the table before the clause was
  /// added, say -- is visible.
  Future<List<({String column, String parent, String onDelete})>> foreignKeysOf(
      String table) async {
    final rows = await _db.rawQuery('PRAGMA foreign_key_list($table)');
    return rows
        .map((r) => (
              column: r['from'] as String,
              parent: r['table'] as String,
              onDelete: (r['on_delete'] as String?) ?? '',
            ))
        .toList();
  }

  /// Deletes a game and everything hanging off it.
  ///
  /// Exists for ONE reason and it is not a feature: the schema declares four
  /// `ON DELETE CASCADE` relations pointing at `games`, and nothing in the app
  /// ever deleted a game, so all four were latent and untested. A cascade nobody
  /// exercises is a cascade nobody knows is broken.
  ///
  /// This is NOT the delete the UI offers. `shelved` replaces delete for the
  /// user, deliberately, and nothing the user recorded is destroyed by it. This
  /// is the honest hard delete, reachable only from code, and it relies on the
  /// cascades rather than deleting children by hand so that the test exercises
  /// the real mechanism.
  Future<void> purgeGame(int igdbId) =>
      _db.delete('games', where: 'igdb_id = ?', whereArgs: [igdbId]);

  static void _validateTitle(String title) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be blank');
    }
    if (title.length > maxNameLength) {
      throw ArgumentError.value(
          title.length, 'title', 'must be at most $maxNameLength characters');
    }
  }

  /// Ratings are 1 to 5, or null for "not rated".
  ///
  /// Throws rather than clamping. A clamp hides the bug at the call site and
  /// writes a number the user never chose, which is worse than a crash in
  /// development and worse than a refusal in production.
  static void _validateRating(int? rating) {
    if (rating == null) return;
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'must be null or 1 to 5');
    }
  }

  /// Opens the real database and seeds it the first time.
  static Future<Repository> open() async {
    final repo = Repository(await openLudeckDatabase());
    await repo.seedIfEmpty();
    return repo;
  }

  /// For tests. Does not seed, so a test starts from a known empty state.
  static Future<Repository> openInMemory() async =>
      Repository(await openInMemoryDatabase());

  // Enum parsing. `byName` throws on an unrecognised value, which is correct:
  // a status this app does not know about is corruption, and defaulting it
  // silently would hide the bug and mislabel the user's game. The throw is
  // contained per row by loadDetailed.

  static Ownership _ownership(String s) => Ownership.values.byName(s);
  static Progress _progress(String s) => Progress.values.byName(s);
  static Form _form(String s) => Form.values.byName(s);
  static Acquired _acquired(String s) => Acquired.values.byName(s);
  static Platform _platform(String s) => Platform.values.byName(s);

  static DateTime? _dateOrNull(Object? v) =>
      v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  /// Everything the tree and the list render from. Shelved rows are excluded.
  Future<List<TreeItem>> load() async => (await loadDetailed()).items;

  /// The same read, but it also reports how many rows it could not parse.
  Future<LoadResult> loadDetailed() async {
    final rows = await _db.rawQuery('''
      SELECT g.igdb_id, g.title, g.cover_url, g.release_year,
             g.time_to_beat_seconds,
             e.ownership, e.progress, e.rating, e.note,
             e.last_played_at, e.recommended_by
      FROM games g
      JOIN entries e ON e.igdb_id = g.igdb_id
      WHERE e.shelved = 0
      ORDER BY g.title COLLATE NOCASE
    ''');
    if (rows.isEmpty) return const LoadResult(items: [], skipped: 0);

    var skipped = 0;

    // Only copies belonging to a live entry. The old query read every copy in
    // the table including those of shelved games, then threw them away.
    final copyRows = await _db.rawQuery('''
      SELECT c.igdb_id, c.platform, c.form, c.acquired, c.price_paid_minor
      FROM copies c
      JOIN entries e ON e.igdb_id = c.igdb_id
      WHERE e.shelved = 0
    ''');
    final byGame = <int, List<Copy>>{};
    for (final c in copyRows) {
      // A copy with an unreadable platform is dropped on its own. Losing one
      // copy is a smaller lie than dropping the game it belongs to.
      try {
        final id = c['igdb_id'] as int;
        byGame.putIfAbsent(id, () => []).add(Copy(
              igdbId: id,
              platform: _platform(c['platform'] as String),
              form: _form(c['form'] as String),
              acquired: _acquired(c['acquired'] as String),
              pricePaidMinor: c['price_paid_minor'] as int?,
            ));
      } catch (_) {
        skipped++;
      }
    }

    final items = <TreeItem>[];
    for (final r in rows) {
      try {
        final id = r['igdb_id'] as int;
        items.add(TreeItem(
          game: Game(
            igdbId: id,
            title: r['title'] as String,
            coverUrl: r['cover_url'] as String?,
            releaseYear: r['release_year'] as int?,
            timeToBeatSeconds: r['time_to_beat_seconds'] as int?,
          ),
          entry: Entry(
            igdbId: id,
            ownership: _ownership(r['ownership'] as String),
            progress: _progress(r['progress'] as String),
            // A rating outside 1 to 5 is treated as absent rather than shown.
            // It cannot get in through this app, so it means the file was
            // edited, and a 7 star game is a worse outcome than no stars.
            rating: _sanitisedRating(r['rating']),
            note: r['note'] as String?,
            lastPlayedAt: _dateOrNull(r['last_played_at']),
            recommendedBy: r['recommended_by'] as String?,
          ),
          copies: byGame[id] ?? const [],
        ));
      } catch (_) {
        skipped++;
      }
    }

    return LoadResult(items: items, skipped: skipped);
  }

  static int? _sanitisedRating(Object? v) {
    if (v is! int) return null;
    if (v < 1 || v > 5) return null;
    return v;
  }

  /// Writes one game, its entry and its copies.
  ///
  /// ### Why this is raw SQL and not `ConflictAlgorithm.replace`
  ///
  /// It used to be `replace` on `games`, and that was the single worst defect in
  /// this file. `INSERT OR REPLACE` in SQLite does not update a row: it DELETES
  /// the conflicting row and inserts a new one. `entries`, `copies` and
  /// `placements` all declare `REFERENCES games(igdb_id) ON DELETE CASCADE`, and
  /// `PRAGMA foreign_keys = ON` is set per connection, so that delete cascaded.
  ///
  /// The effect: re-importing a game you already had silently destroyed its
  /// progress, its rating, its note, every platform you owned it on, and every
  /// branch it hung from. The one promise this model exists to make, that a
  /// completion record survives everything, was being broken by an ordinary
  /// second import. No feature test touched it because nothing imported twice.
  ///
  /// `ON CONFLICT DO UPDATE` updates in place. No delete, so no cascade.
  ///
  /// The three tables then have three deliberate rules:
  /// - `games` updates, because it is catalogue data owned by IGDB and a
  ///   corrected title or length should win.
  /// - `entries` does nothing on conflict. Only the user changes an entry.
  /// - `copies` does nothing on conflict, so a re-import cannot duplicate a copy.
  Future<void> upsert(TreeItem item) async {
    final g = item.game;
    final e = item.entry;
    _validateTitle(g.title);
    _validateRating(e.rating);
    await _db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT INTO games
          (igdb_id, title, cover_url, release_year, time_to_beat_seconds)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(igdb_id) DO UPDATE SET
          title                = excluded.title,
          cover_url            = excluded.cover_url,
          release_year         = excluded.release_year,
          time_to_beat_seconds = excluded.time_to_beat_seconds
        ''',
        [
          g.igdbId,
          g.title,
          g.coverUrl,
          g.releaseYear,
          g.timeToBeatSeconds,
        ],
      );
      await txn.rawInsert(
        '''
        INSERT INTO entries
          (igdb_id, ownership, progress, rating, note, last_played_at,
           recommended_by, shelved)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(igdb_id) DO NOTHING
        ''',
        [
          e.igdbId,
          e.ownership.name,
          e.progress.name,
          e.rating,
          e.note,
          e.lastPlayedAt?.millisecondsSinceEpoch,
          e.recommendedBy,
          e.shelved ? 1 : 0,
        ],
      );
      for (final c in item.copies) {
        await txn.insert(
          'copies',
          {
            'igdb_id': c.igdbId,
            'platform': c.platform.name,
            'form': c.form.name,
            'acquired': c.acquired.name,
            'price_paid_minor': c.pricePaidMinor,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Sets ownership and touches nothing else.
  ///
  /// Two separate methods rather than one with two optional arguments. One
  /// method is exactly how the two axes get accidentally coupled by a caller
  /// that passes both, and keeping a completion record through a sale is the
  /// reason this model exists.
  Future<void> setOwnership(int igdbId, Ownership value) => _db.update(
        'entries',
        {'ownership': value.name},
        where: 'igdb_id = ?',
        whereArgs: [igdbId],
      );

  /// Sets progress and touches nothing else.
  Future<void> setProgress(int igdbId, Progress value) => _db.update(
        'entries',
        {'progress': value.name},
        where: 'igdb_id = ?',
        whereArgs: [igdbId],
      );

  /// Sets the rating and touches nothing else. Null clears it.
  ///
  /// A rating belongs to the harvest, not to the game, so this deliberately does
  /// not also set progress. Rating something you have not finished is a caller
  /// bug and the UI is what prevents it, not this method: the repository's job
  /// is to refuse impossible VALUES, not to enforce a screen's flow.
  Future<void> setRating(int igdbId, int? rating) {
    _validateRating(rating);
    return _db.update(
      'entries',
      {'rating': rating},
      where: 'igdb_id = ?',
      whereArgs: [igdbId],
    );
  }

  /// Records a cover image found for a game that had none, and touches
  /// nothing else.
  ///
  /// Separate from `upsert` deliberately: this is filled in AFTER the fact by a
  /// lazy lookup (`CoverArtService`), often long after the row was written, and
  /// a method that also re-writes ownership/progress/copies would risk a stale
  /// caller resetting those. It only ever moves a game from no cover to a
  /// cover -- callers never overwrite an existing one, so a live IGDB cover
  /// can never be replaced by a weaker guess.
  Future<void> setCoverUrl(int igdbId, String coverUrl) => _db.update(
        'games',
        {'cover_url': coverUrl},
        where: 'igdb_id = ?',
        whereArgs: [igdbId],
      );

  /// Replaces delete.
  Future<void> shelve(int igdbId) => _db.update(
        'entries',
        {'shelved': 1},
        where: 'igdb_id = ?',
        whereArgs: [igdbId],
      );

  /// Brings a shelved game back.
  ///
  /// Shelving replaces deletion, so it has to be reversible or it is just a
  /// delete with a gentler name. Without this the user has no way back and the
  /// promise the word makes is false.
  Future<void> unshelve(int igdbId) => _db.update(
        'entries',
        {'shelved': 0},
        where: 'igdb_id = ?',
        whereArgs: [igdbId],
      );

  /// Removes one copy without touching the entry. This is a sale, and the
  /// completion record must survive it.
  Future<void> removeCopy(int igdbId, Platform platform, Form form) =>
      _db.delete(
        'copies',
        where: 'igdb_id = ? AND platform = ? AND form = ?',
        whereArgs: [igdbId, platform.name, form.name],
      );

  // Branches, named by the user.

  /// Normalises a user supplied branch name, or throws.
  ///
  /// Trimmed, because a name that is only spaces is unreadable in a list and
  /// unselectable by search, and the user cannot see the difference. Length
  /// capped, because nothing downstream can lay out an unbounded paste.
  static String _branchName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(raw, 'name', 'a branch needs a name');
    }
    if (name.length > maxNameLength) {
      throw ArgumentError.value(
          name.length, 'name', 'must be at most $maxNameLength characters');
    }
    return name;
  }

  Future<int> createBranch(String name, {int sortOrder = 0}) => _db.insert(
        'branches',
        {
          'name': _branchName(name),
          'sort_order': sortOrder,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
      );

  Future<List<Branch>> branches() async {
    final rows = await _db.query('branches', orderBy: 'sort_order, id');
    return rows
        .map((r) => (
              id: r['id'] as int,
              name: r['name'] as String,
              sortOrder: r['sort_order'] as int,
            ))
        .toList();
  }

  Future<void> renameBranch(int id, String name) => _db.update(
        'branches',
        {'name': _branchName(name)},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Removes a branch and the placements that pointed at it.
  ///
  /// It does NOT remove a single game, entry or copy. A branch is a container,
  /// and emptying a container does not destroy what was inside: the games simply
  /// become unplaced, which is an ordinary state with its own UI. The schema's
  /// cascade would handle placements on its own, but only because
  /// `PRAGMA foreign_keys = ON` is set per connection, so the delete is written
  /// out explicitly rather than trusting that to stay true.
  Future<void> deleteBranch(int id) => _db.transaction((txn) async {
        await txn.delete('placements', where: 'branch_id = ?', whereArgs: [id]);
        await txn.delete('branches', where: 'id = ?', whereArgs: [id]);
      });

  /// Rewrites the order of every branch in one transaction.
  ///
  /// One transaction because a reorder that fails halfway leaves two branches
  /// claiming the same position, and the list then renders in an order that
  /// depends on the id tiebreak rather than on anything the user did.
  Future<void> reorderBranches(List<int> idsInOrder) => _db.transaction((txn) async {
        for (var i = 0; i < idsInOrder.length; i++) {
          await txn.update(
            'branches',
            {'sort_order': i},
            where: 'id = ?',
            whereArgs: [idsInOrder[i]],
          );
        }
      });

  Future<void> place(int igdbId, int branchId, {int position = 0}) => _db.insert(
        'placements',
        {'branch_id': branchId, 'igdb_id': igdbId, 'position': position},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> unplace(int igdbId, int branchId) => _db.delete(
        'placements',
        where: 'branch_id = ? AND igdb_id = ?',
        whereArgs: [branchId, igdbId],
      );

  /// Which games hang on which branch, keyed by branch id.
  ///
  /// One query rather than one per branch: grouping the collection needs every
  /// placement at once, and N+1 reads on every load would scale with the number
  /// of branches a user makes.
  ///
  /// Shelved games are excluded, matching `loadDetailed`. A placement pointing at
  /// a shelved game is not wrong, it is simply not shown, and leaving it in would
  /// make a branch's count disagree with the rows under it.
  Future<Map<int, List<int>>> placements() async {
    final rows = await _db.rawQuery('''
      SELECT p.branch_id, p.igdb_id FROM placements p
      JOIN entries e ON e.igdb_id = p.igdb_id
      JOIN games   g ON g.igdb_id = p.igdb_id
      WHERE e.shelved = 0
      ORDER BY p.branch_id, p.position, g.title COLLATE NOCASE
    ''');
    final out = <int, List<int>>{};
    for (final r in rows) {
      final branchId = r['branch_id'] as int;
      (out[branchId] ??= <int>[]).add(r['igdb_id'] as int);
    }
    return out;
  }

  /// Games captured but not yet placed on any branch.
  ///
  /// This is a real state with its own UI, not an error. It is what the "NEW"
  /// ribbon and the unplaced section in docs/USERFLOWS.md refer to.
  Future<List<int>> unplacedGameIds() async {
    final rows = await _db.rawQuery('''
      SELECT g.igdb_id FROM games g
      JOIN entries e ON e.igdb_id = g.igdb_id
      WHERE e.shelved = 0
        AND g.igdb_id NOT IN (SELECT igdb_id FROM placements)
      ORDER BY g.title COLLATE NOCASE
    ''');
    return rows.map((r) => r['igdb_id'] as int).toList();
  }

  Future<int> gameCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM games');
    return (r.first['n'] as int?) ?? 0;
  }

  /// Fills an empty database from the fixture so a first run has something to
  /// look at. Does nothing once there is any real data.
  Future<void> seedIfEmpty() async {
    if (await gameCount() > 0) return;
    for (final item in fixtureTree()) {
      await upsert(item);
    }
  }

  // ---------------------------------------------------------------------------
  // Sources. Where a game came from.
  // ---------------------------------------------------------------------------

  /// Records where a game came from. Returns the new row id, or 0 when this
  /// exact link was already recorded for this game.
  ///
  /// Re-sharing one link is a NO-OP rather than a duplicate or an overwrite.
  /// `sources` is a leaf table so `replace` would not cascade, but ignore is
  /// the correct semantic: the first capture is the true one, and a later share
  /// of the same link should not quietly rewrite the title it was saved under.
  Future<int> addSource(Source s) => _db.insert(
        'sources',
        {
          'igdb_id': s.igdbId,
          'url': s.url,
          'kind': s.kind.name,
          'match_method': s.matchMethod.name,
          'title': s.title,
          'channel': s.channel,
          'thumb_url': s.thumbUrl,
          'added_at': s.addedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// Every recorded source for one game, newest first.
  Future<List<Source>> sourcesFor(int igdbId) async {
    final rows = await _db.query(
      'sources',
      where: 'igdb_id = ?',
      whereArgs: [igdbId],
      orderBy: 'added_at DESC, id DESC',
    );
    return rows.map(_source).toList();
  }

  /// Forgets one source. Unlike a collection row this IS a real delete: the
  /// user asking to forget where something came from is asking for exactly
  /// that, and no progress or ownership data hangs off it.
  Future<void> removeSource(int id) =>
      _db.delete('sources', where: 'id = ?', whereArgs: [id]);

  Source _source(Map<String, Object?> r) => Source(
        id: r['id'] as int?,
        igdbId: r['igdb_id'] as int,
        url: r['url'] as String?,
        kind: _sourceKind(r['kind'] as String),
        matchMethod: _matchMethod(r['match_method'] as String),
        title: r['title'] as String?,
        channel: r['channel'] as String?,
        thumbUrl: r['thumb_url'] as String?,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
      );

  // These two parse tolerantly, unlike the collection enums above, and the
  // asymmetry is deliberate.
  //
  // An unrecognised value in `entries` means the row's MEANING is unknown, so
  // `loadDetailed` skips it and says so. A source's url is still perfectly good
  // data when its badge is unreadable, and losing the link would be the greater
  // harm.
  //
  // Both fall back to the LEAST trusted value in their enum, so a corrupt row
  // can never claim to be an exact match it cannot prove.
  static SourceKind _sourceKind(String s) {
    for (final k in SourceKind.values) {
      if (k.name == s) return k;
    }
    return SourceKind.web;
  }

  static MatchMethod _matchMethod(String s) {
    for (final m in MatchMethod.values) {
      if (m.name == s) return m;
    }
    return MatchMethod.text;
  }

  Future<void> close() => _db.close();
}
