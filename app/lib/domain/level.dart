// Level and progress, derived from the collection -- never invented.
//
// The ONE fact this is allowed to be built on is how many games the user has
// HARVESTED (finished). `docs/DECISIONS.md` is explicit that "gamification may
// only reward what already happened, never mark what has not", and that the
// metaphor "may never wither, rot, nag, empty or shrink". A harvest count only
// ever goes up, so a level derived from it can only ever go up too.
//
// Deliberately NOT used as inputs:
//   * time since last played -- that is decay, and decay is forbidden
//   * a streak -- "seasons, not streaks"; a streak punishes a missed day
//   * games owned but unfinished -- that would make the number a backlog gauge,
//     which is the thing this app exists not to be
//
// Pure functions in the domain layer, so the numbers can be tested without a
// widget or a database. A level shown on screen that nothing verifies is how a
// fake number ships.

/// Harvests needed to REACH each level, cumulative. Index 0 is level 1.
///
/// Triangular-ish and hand-written rather than a formula, because the early
/// steps matter most: reaching level 2 on your first finished game is the moment
/// the number starts meaning something, so it costs one, not five. Later steps
/// widen so the number keeps moving without inflating.
const List<int> kLevelThresholds = [
  0, // level 1 -- you have a tree
  1, // level 2 -- one harvest
  3,
  6,
  10,
  15,
  21,
  28,
  36,
  45,
  55,
];

/// Where the user is, given how many games they have harvested.
///
/// [level] starts at 1 and never drops. [progress] is 0..1 toward the next
/// level, and is 1.0 at the top of the table -- a finished ladder reads as
/// complete rather than as stuck at 0.
({int level, double progress, int harvestedIntoLevel, int neededForNext})
    levelFor(int harvested) {
  // Negative is not reachable from the collection, but clamping is cheaper than
  // trusting every future caller.
  final done = harvested < 0 ? 0 : harvested;

  var index = 0;
  for (var i = 0; i < kLevelThresholds.length; i++) {
    if (done >= kLevelThresholds[i]) index = i;
  }

  final atTop = index >= kLevelThresholds.length - 1;
  if (atTop) {
    return (
      level: index + 1,
      progress: 1.0,
      harvestedIntoLevel: done - kLevelThresholds[index],
      neededForNext: 0,
    );
  }

  final floor = kLevelThresholds[index];
  final ceiling = kLevelThresholds[index + 1];
  final span = ceiling - floor;
  final into = done - floor;

  return (
    level: index + 1,
    // span is never 0 for a non-top level because the table is strictly
    // increasing, but the guard keeps a bad edit from producing NaN on screen.
    progress: span <= 0 ? 1.0 : (into / span).clamp(0.0, 1.0),
    harvestedIntoLevel: into,
    neededForNext: ceiling - done,
  );
}
