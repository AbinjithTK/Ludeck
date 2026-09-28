import 'dart:math' as math;

import '../data/enums.dart';
import '../data/models.dart';

/// A suggestion, with the reason it was chosen. The reason is the product: a
/// coloured dot asks the user to learn what the colour means, a sentence does
/// not.
class Pick {
  const Pick({required this.item, required this.reason});
  final TreeItem item;
  final String reason;

  @override
  String toString() => 'Pick(${item.game.title}: $reason)';
}

/// Choose one game to play tonight.
///
/// [hoursFree] is how long the player has, in hours. Omit it to mean no time
/// limit. [devices] is what is within reach right now; an empty set means no
/// device filter at all.
///
/// Returns null when nothing survives the filters. That is a real state, not
/// an error, and the caller must have something to say for it: an empty
/// collection, everything already finished, or a time budget nothing fits.
Pick? choosePick(
  List<TreeItem> items, {
  double? hoursFree,
  Set<Platform> devices = const {},
}) {
  // Step 1 to 3: only games actually available to play right now.
  var candidates = items.where((i) =>
      !i.entry.shelved &&
      i.entry.ownership == Ownership.owned &&
      i.entry.progress != Progress.finished &&
      i.entry.progress != Progress.abandoned);

  // Step 4: filter to the devices at hand, when the caller named any.
  if (devices.isNotEmpty) {
    candidates = candidates.where((i) => i.platforms.any(devices.contains));
  }

  // Step 6: drop anything KNOWN to be longer than the time available. An
  // unknown length is kept rather than dropped, because IGDB having no length
  // on file is not the same fact as the game being too long, and treating an
  // unknown as disqualifying would silently shrink the pool for reasons the
  // user cannot see.
  if (hoursFree != null) {
    candidates = candidates.where((i) {
      final h = i.game.hours;
      return h == null || h <= hoursFree;
    });
  }

  final pool = candidates.toList();
  if (pool.isEmpty) return null;

  // Step 5 then 7: continuation beats hours. Something already in hand is the
  // easiest thing to pick back up, and that ordering is checked before length
  // at all, so a short game you have not touched never jumps ahead of a
  // shorter one you are already mid-way through.
  int continuationRank(Progress p) => switch (p) {
        Progress.playing => 0,
        Progress.installed => 1,
        Progress.untouched => 2,
        Progress.finished || Progress.abandoned => 3, // excluded above; unreached
      };

  pool.sort((a, b) {
    final byContinuation = continuationRank(a.entry.progress)
        .compareTo(continuationRank(b.entry.progress));
    if (byContinuation != 0) return byContinuation;

    // Shortest known length wins a tie. Unknown length sorts last: an unknown
    // is being given the benefit of the doubt by surviving the filter above,
    // but it should not be preferred over a game whose length is actually
    // known to be short.
    final ah = a.game.hours;
    final bh = b.game.hours;
    if (ah == null && bh == null) return 0;
    if (ah == null) return 1;
    if (bh == null) return -1;
    return ah.compareTo(bh);
  });

  final chosen = pool.first;
  return Pick(item: chosen, reason: _reasonFor(chosen, hoursFree));
}

/// Builds a reason that is true of the specific item chosen. Never a reason
/// that merely sounds encouraging: if the pick was chosen for being already in
/// hand, the reason says that, not something generic about the game being
/// good.
String _reasonFor(TreeItem item, double? hoursFree) {
  final hours = item.game.hours;

  switch (item.entry.progress) {
    case Progress.playing:
      return hours == null
          ? 'Already in hand.'
          : 'Already in hand, about $hours ${hours == 1 ? 'hour' : 'hours'} left.';
    case Progress.installed:
      return 'Installed and ready to pick back up.';
    case Progress.untouched:
      if (hours == null) {
        return 'Not started yet.';
      }
      if (hoursFree != null && hours <= hoursFree) {
        return 'Short enough for tonight, about $hours '
            '${hours == 1 ? 'hour' : 'hours'}.';
      }
      return 'Not started yet, about $hours ${hours == 1 ? 'hour' : 'hours'}.';
    case Progress.finished:
    case Progress.abandoned:
      // Unreachable: both are filtered out before a candidate can be chosen.
      return 'Not started yet.';
  }
}

/// Shake the tree: one game, at random, from what on it can be played now.
///
/// The roulette. Not uniform: a game already in hand is three times as likely
/// to fall as one not started, and an installed one twice, because the point
/// of shaking is to get something you will actually pick up tonight. Anything
/// finished, set aside, not owned (a bud) or shelved never falls. [avoid] is
/// the last game that fell: "shake again" never hands back the same game while
/// there is another. Null when nothing on the tree can fall.
Pick? shakePick(List<TreeItem> items, math.Random rnd, {int? avoid}) {
  var pool = items
      .where((i) =>
          !i.entry.shelved &&
          i.entry.ownership == Ownership.owned &&
          i.entry.progress != Progress.finished &&
          i.entry.progress != Progress.abandoned)
      .toList();
  if (pool.isEmpty) return null;
  if (avoid != null && pool.length > 1) {
    pool = pool.where((i) => i.game.igdbId != avoid).toList();
  }
  int weight(TreeItem i) => switch (i.entry.progress) {
        Progress.playing => 3,
        Progress.installed => 2,
        _ => 1,
      };
  final total = pool.fold<int>(0, (s, i) => s + weight(i));
  var r = rnd.nextInt(total);
  for (final i in pool) {
    r -= weight(i);
    if (r < 0) return Pick(item: i, reason: _reasonFor(i, null));
  }
  return Pick(item: pool.last, reason: _reasonFor(pool.last, null));
}
