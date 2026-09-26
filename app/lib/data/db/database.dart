// Plain SQL, deliberately. Code generation is not available on this toolchain:
// Flutter 3.38.9 pins meta 1.17.0, which caps analyzer at 10.0.1, which caps
// build_runner at 2.15.1, which invokes `dart compile`, which Dart SDK 3.10.8
// refuses. See docs/CONSTRAINTS.md. Five tables do not need an ORM anyway.

// dart:io also exports `Platform`, which is one of our own enums. Prefixed so
// the collision cannot happen.
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// Prefixed because this package re-exports all of sqflite, and importing both
// unprefixed makes the sqflite import look redundant. Only two symbols here are
// genuinely ffi-specific.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// The file name. docs/DECISIONS.md froze `ludeck.db` and this honours it.
const String kDatabaseFile = 'ludeck.db';

const int kSchemaVersion = 3;

/// Where a game came from. Added in schema v2.
///
/// Held as a named constant because BOTH `_ddl` (fresh install) and
/// `_migrations[2]` (existing install) must produce a byte-identical table. Two
/// copies of this SQL would drift, and the drift would only show up on one of
/// the two paths, which is the worst way to find it.
///
/// One game may have MANY sources. A second video about a game you already have
/// is information, not a duplicate, so this is a set of rows rather than a
/// column on `games`.
///
/// `url` is nullable because shared prose carries no link. SQLite treats NULLs
/// as distinct in a UNIQUE constraint, so two friends recommending the same
/// game in two messages correctly produce two rows, while re-sharing one link
/// stays idempotent.
///
/// PRIVACY: `channel` names a real third party, exactly like
/// `entries.recommended_by`. docs/DECISIONS.md invariant 10 keeps both off the
/// share layer, which takes title, cover, status and rating only.
const String _sourcesTable = '''
  CREATE TABLE IF NOT EXISTS sources (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    igdb_id       INTEGER NOT NULL REFERENCES games(igdb_id) ON DELETE CASCADE,
    url           TEXT,
    kind          TEXT    NOT NULL,
    match_method  TEXT    NOT NULL,
    title         TEXT,
    channel       TEXT,
    thumb_url     TEXT,
    added_at      INTEGER NOT NULL,
    UNIQUE (igdb_id, url)
  )
  ''';

const String _sourcesIndex =
    'CREATE INDEX IF NOT EXISTS idx_sources_game ON sources(igdb_id)';

/// The user's chosen order of games on the roadmap. Added in schema v3.
///
/// A separate table rather than a column on `entries`, for the same reason
/// placements are a join and not a field: it is additive, needs no change to
/// the `Entry` model or its many read/write paths, and a game with no row here
/// is simply unordered (it falls to the end in a stable default order), which
/// is a real state — every game before the user first reorders anything.
///
/// Held as a named constant because BOTH `_ddl` (fresh install) and
/// `_migrations[3]` (existing install) must produce a byte-identical table.
const String _roadmapOrderTable = '''
  CREATE TABLE IF NOT EXISTS roadmap_order (
    igdb_id  INTEGER PRIMARY KEY REFERENCES games(igdb_id) ON DELETE CASCADE,
    position INTEGER NOT NULL
  )
  ''';

/// Every table, in dependency order.
///
/// Read this before changing anything. The comments are load-bearing: each one
/// records an invariant from docs/DECISIONS.md that a later "simplification"
/// would break.
const List<String> _ddl = [
  // Catalogue. One row per IGDB id.
  //
  // igdb_id is the primary key because it is the only identity. There is
  // deliberately NO unique index on title: titles collide, get re-released and
  // differ by region, and matching on one is the fastest way to corrupt this.
  //
  // time_to_beat_seconds is SECONDS, exactly as IGDB returns them. Never hours.
  '''
  CREATE TABLE IF NOT EXISTS games (
    igdb_id              INTEGER PRIMARY KEY,
    title                TEXT    NOT NULL,
    cover_url            TEXT,
    release_year         INTEGER,
    time_to_beat_seconds INTEGER
  )
  ''',

  // The user's relationship to a game. Exactly one row per game.
  //
  // ownership and progress are two INDEPENDENT axes. Nothing may couple them.
  // Merging them into one column is a product regression, not a simplification:
  // a single chain cannot express "I finished it and then sold it".
  //
  // shelved replaces delete. Nothing the user recorded is destroyed.
  '''
  CREATE TABLE IF NOT EXISTS entries (
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

  // Owned copies. A SET of rows, never a field on the game.
  //
  // Two rows for one game is normal: the same game on PC and on Switch, or a
  // physical and a digital copy. Selling one must not touch the other and must
  // not touch entries at all.
  //
  // The UNIQUE constraint stops a re-import creating a second identical copy,
  // which would make one game hang twice on one branch for no reason.
  '''
  CREATE TABLE IF NOT EXISTS copies (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    igdb_id          INTEGER NOT NULL REFERENCES games(igdb_id) ON DELETE CASCADE,
    platform         TEXT    NOT NULL,
    form             TEXT    NOT NULL,
    acquired         TEXT    NOT NULL,
    price_paid_minor INTEGER,
    UNIQUE (igdb_id, platform, form)
  )
  ''',

  // A branch, named by the user.
  //
  // Branches are NOT derived from platforms. That was an earlier design and it
  // is superseded: arbitrary, unlimited categorisation is what gives each tree
  // its own shape.
  '''
  CREATE TABLE IF NOT EXISTS branches (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT    NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',

  // Which game hangs on which branch.
  //
  // A join, not a field, because a game may legitimately sit on more than one
  // branch. A game with no row here is captured but UNPLACED, which is a real
  // state the UI shows rather than an error.
  '''
  CREATE TABLE IF NOT EXISTS placements (
    branch_id INTEGER NOT NULL REFERENCES branches(id)    ON DELETE CASCADE,
    igdb_id   INTEGER NOT NULL REFERENCES games(igdb_id)  ON DELETE CASCADE,
    position  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (branch_id, igdb_id)
  )
  ''',

  _sourcesTable,

  _roadmapOrderTable,

  'CREATE INDEX IF NOT EXISTS idx_copies_game ON copies(igdb_id)',
  'CREATE INDEX IF NOT EXISTS idx_placements_game ON placements(igdb_id)',
  _sourcesIndex,
];

/// Call once before opening a database on Windows, Linux or macOS.
///
/// On Android and iOS sqflite works as shipped and this is a no-op.
void initDatabasePlatform() {
  if (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  }
}

/// Opens the real on-disk database.
Future<Database> openLudeckDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  return openLudeckDatabaseAt(p.join(dir.path, kDatabaseFile));
}

/// Opens the database at an explicit path.
///
/// Exists so migration tests run THIS code rather than a copy of it: a
/// migration verified against a duplicated opener proves nothing about the one
/// that ships. `getApplicationDocumentsDirectory` needs platform channels that
/// a plain unit test does not have, which is the only reason the split exists.
Future<Database> openLudeckDatabaseAt(String path) async {
  initDatabasePlatform();
  return openDatabase(
    path,
    version: kSchemaVersion,
    onConfigure: _onConfigure,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
}

/// Opens an in-memory database. For tests, and for nothing else.
Future<Database> openInMemoryDatabase() async {
  initDatabasePlatform();
  return openDatabase(
    inMemoryDatabasePath,
    version: kSchemaVersion,
    onConfigure: _onConfigure,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
}

/// Foreign keys are OFF by default in SQLite and must be enabled per
/// connection. Without this the ON DELETE CASCADE clauses above are decoration.
Future<void> _onConfigure(Database db) =>
    db.execute('PRAGMA foreign_keys = ON');

Future<void> _onCreate(Database db, int version) async {
  final batch = db.batch();
  for (final statement in _ddl) {
    batch.execute(statement);
  }
  await batch.commit(noResult: true);
}

/// Migrations, keyed by the version each one PRODUCES.
///
/// `_migrations[2]` takes a v1 database to v2. They run in sequence, so a user
/// who skipped a release upgrades 1 -> 2 -> 3 rather than being a special case
/// nobody tested.
///
/// Every step must be additive or explicitly rewrite data it owns. Dropping and
/// recreating a table destroys a real collection and is never the answer.
const Map<int, List<String>> _migrations = {
  2: [_sourcesTable, _sourcesIndex],
  3: [_roadmapOrderTable],
};

/// Versions `_migrations` can produce.
///
/// Exposed so a test can assert every version from 2 to [kSchemaVersion] has a
/// step. The mistake that needs catching is bumping the constant and forgetting
/// the map entry, which a fresh install never notices and every existing
/// install hits on first open.
Iterable<int> get kMigrationVersions => _migrations.keys;

Future<void> _onUpgrade(Database db, int from, int to) async {
  for (var version = from + 1; version <= to; version++) {
    final steps = _migrations[version];
    if (steps == null) {
      throw UnsupportedError(
        'No migration to schema $version exists. Add one to _migrations in '
        'database.dart rather than recreating the tables, which would destroy '
        'a real collection.',
      );
    }
    final batch = db.batch();
    for (final statement in steps) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }
}
