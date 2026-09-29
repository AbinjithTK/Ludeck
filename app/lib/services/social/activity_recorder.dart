// Turns what you do in your own orchard into the quiet feed friends read.
//
// It watches the collection, not the buttons. Games arrive by share, search,
// a graft from a friend or a seed from the inbox; a game is finished from the
// sheet or the library. Hooking each path would miss the next one someone
// adds. Watching the store and comparing before and after catches all of
// them: a new game is `planted`, a move into finished is `harvested`, a new
// rating is `rated`.
//
// PRIVACY -- invariant 10. An event carries the game's id, title, cover and,
// for a rating, your own rating. Never the note, never who recommended it,
// never the video it came from. The server shows it only to people allowed to
// see your tree (0003 `can_view`), so a friends-only profile's events reach
// accepted followers only.
//
// Off with one switch (Settings > Account), stored on the phone. Nothing is
// posted signed out, and nothing on the first read of the collection: that is
// the library you already had, not news.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../state/ludeck_store.dart';
import 'social_backend.dart';

const _prefKey = 'share_activity_v1';

/// Whether your plants, harvests and ratings go to friends. On by default,
/// because the feed is empty for everyone otherwise; one switch turns it off.
class ActivitySharing {
  ActivitySharing._();

  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> set(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

typedef _Snap = ({Progress progress, int? rating});

class ActivityRecorder {
  ActivityRecorder(this._source, this._read, this._backend,
      {ValueListenable<bool>? enabled})
      : _enabled = enabled ?? ActivitySharing.enabled;

  /// Watches the app's store.
  factory ActivityRecorder.forStore(LudeckStore store, SocialBackend backend,
          {ValueListenable<bool>? enabled}) =>
      ActivityRecorder(store, () => store.items, backend, enabled: enabled);

  final Listenable _source;
  final List<TreeItem>? Function() _read;
  final SocialBackend _backend;
  final ValueListenable<bool> _enabled;

  Map<int, _Snap>? _last;

  /// A bulk change (an import, a restore) is not news. Past this many events
  /// in one change, none are posted.
  static const maxPerChange = 5;

  void attach() => _source.addListener(_onChange);

  void detach() => _source.removeListener(_onChange);

  void _onChange() {
    final items = _read();
    if (items == null) return;
    final now = {
      for (final i in items)
        i.game.igdbId: (progress: i.entry.progress, rating: i.entry.rating),
    };
    final before = _last;
    _last = now;
    if (before == null) return; // the first read is the library, not news
    if (!_backend.isConfigured || _backend.currentProfile == null) return;
    if (!_enabled.value) return;

    final byId = {for (final i in items) i.game.igdbId: i};
    final events = <(ActivityKind, TreeItem)>[];
    for (final MapEntry(key: id, value: s) in now.entries) {
      final was = before[id];
      final item = byId[id]!;
      if (was == null) {
        events.add((ActivityKind.planted, item));
        continue;
      }
      if (s.progress == Progress.finished && was.progress != Progress.finished) {
        events.add((ActivityKind.harvested, item));
      }
      if (s.rating != null && s.rating != was.rating) {
        events.add((ActivityKind.rated, item));
      }
    }
    if (events.isEmpty || events.length > maxPerChange) return;
    for (final (kind, item) in events) {
      unawaited(_post(kind, item));
    }
  }

  Future<void> _post(ActivityKind kind, TreeItem item) async {
    try {
      await _backend.postActivity(
        kind: kind,
        igdbId: item.game.igdbId,
        title: item.game.title,
        coverUrl: item.game.coverUrl,
        rating: kind == ActivityKind.rated ? item.entry.rating : null,
      );
    } on SocialException {
      // Offline or signed out mid-way: a missed feed line is not worth an
      // error on the screen. The orchard itself is already saved.
    }
  }
}
