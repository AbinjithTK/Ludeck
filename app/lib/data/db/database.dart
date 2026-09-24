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

const int kSchemaVersion = 1;

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

  'CREATE INDEX IF NOT EXISTS idx_copies_game ON copies(igdb_id)',
  'CREATE INDEX IF NOT EXISTS idx_placements_game ON placements(igdb_id)',
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
  initDatabasePlatform();
  final dir = await getApplicationDocumentsDirectory();
  return openDatabase(
    p.join(dir.path, kDatabaseFile),
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

/// There is no version 2 yet. When there is, add a case; never drop and
/// recreate, because that destroys a real collection.
Future<void> _onUpgrade(Database db, int from, int to) async {
  throw UnsupportedError(
    'No migration from schema $from to $to exists yet. '
    'Add one in database.dart rather than recreating the tables.',
  );
}
