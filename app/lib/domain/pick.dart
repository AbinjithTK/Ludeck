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

/// Shake the tree: one game, at random, from everything hanging on it.
///
/// The roulette. Every fruit that hangs can fall: a roulette where two of six
/// fruit ever came down read as broken (2026-09-28, when only owned,
/// unfinished games could fall), and so does a fruit you can see that never
/// comes down (a given-away game kept on the tree). It is still not uniform:
/// what you can play tonight falls far more often than a bud, a finished
/// game or one given away, and [reason] says honestly why each one came down.
///
/// [fallen] is what already fell this round: a game does not fall twice
/// until every other game on the tree has had its turn (a shuffle bag, so a
/// run of shakes goes round the whole tree instead of re-rolling the same
/// favourite). When the round is spent it starts again, still never handing
/// back [avoid], the one that just fell, while there is another. Null when
/// nothing on the tree can fall.
Pick? shakePick(List<TreeItem> items, math.Random rnd,
    {int? avoid, Set<int> fallen = const {}}) {
  final pool = [...items];
  if (pool.isEmpty) return null;
  var bag = pool.where((i) => !fallen.contains(i.game.igdbId)).toList();
  if (bag.isEmpty) bag = pool; // the round is spent: a new one
  if (avoid != null && bag.length > 1) {
    bag = bag.where((i) => i.game.igdbId != avoid).toList();
  }
  final total = bag.fold<int>(0, (s, i) => s + shakeWeight(i));
  var r = rnd.nextInt(total);
  for (final i in bag) {
    r -= shakeWeight(i);
    if (r < 0) return Pick(item: i, reason: _shakeReason(i));
  }
  return Pick(item: bag.last, reason: _shakeReason(bag.last));
}

/// How likely [i] is to fall, relative to the others still in the bag. The
/// point of shaking is something you will actually pick up tonight, so a
/// game in hand is six times as likely as a finished one.
int shakeWeight(TreeItem i) {
  if (i.entry.ownership == Ownership.released) return 1;
  if (i.entry.ownership != Ownership.owned) return 2; // a bud
  if (i.entry.shelved) return 1;
  return switch (i.entry.progress) {
    Progress.playing => 6,
    Progress.installed => 4,
    Progress.untouched => 3,
    Progress.finished || Progress.abandoned => 1,
  };
}

String _shakeReason(TreeItem i) {
  if (i.entry.ownership == Ownership.released) {
    return 'Given away a while back. Miss it?';
  }
  if (i.entry.ownership != Ownership.owned) {
    return 'A bud: not yours yet. Worth picking up?';
  }
  if (i.entry.shelved) return 'On the shelf a while. Another look?';
  return switch (i.entry.progress) {
    Progress.finished => 'Finished already. Up for a replay?',
    Progress.abandoned => 'Set aside a while back. Another go?',
    _ => _reasonFor(i, null),
  };
}

/// Per-tree memory of what fell this round, for [shakePick]'s shuffle bag.
/// Lives as long as the orchard screen: a new session starts a new round.
class ShakeBag {
  final Map<int, Set<int>> _fallen = {};
  final Map<int, int> _last = {};

  /// Shake tree [treeId] holding [hanging]. The game that fell last is never
  /// handed straight back while there is another.
  Pick? shake(int treeId, List<TreeItem> hanging, math.Random rnd) {
    final done = _fallen.putIfAbsent(treeId, () => <int>{});
    final ids = hanging.map((i) => i.game.igdbId).toSet();
    done.retainAll(ids); // a game moved off the tree leaves the round
    if (done.length >= ids.length) done.clear();
    final pick = shakePick(hanging, rnd, avoid: _last[treeId], fallen: done);
    if (pick != null) {
      done.add(pick.item.game.igdbId);
      _last[treeId] = pick.item.game.igdbId;
    }
    return pick;
  }
}
