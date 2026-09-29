// Lately: what friends planted, finished and rated in the last two weeks.
//
// Direction B from the 2026-09-29 design pass, the "quiet feed": real events
// only, newest first, and it ends. The last line says so. There are no counts
// on anything, and a hype is seen by the owner alone.
//
// Each line offers the two things a friend's news is for: hype it, or graft
// the game onto your own tree.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../account/account_widgets.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';
import 'graft.dart';

/// "just now", "5m", "3h", "Yesterday", "4d".
String whenLabel(DateTime at, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays}d';
}

String activitySentence(ActivityItem a) => switch (a.kind) {
      ActivityKind.planted => 'planted ${a.title}',
      ActivityKind.harvested => 'finished ${a.title}',
      ActivityKind.rated => a.rating == null
          ? 'rated ${a.title}'
          : 'rated ${a.title} ${a.rating} of 5',
    };

class LatelyScreen extends StatefulWidget {
  const LatelyScreen({super.key});

  @override
  State<LatelyScreen> createState() => _LatelyScreenState();
}

class _LatelyScreenState extends State<LatelyScreen> {
  late Future<List<ActivityItem>> _feed;

  /// Hypes you gave, per friend: handle -> game ids.
  final Map<String, Set<int>> _hyped = {};

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    _feed = _load();
  }

  Future<List<ActivityItem>> _load() async {
    final items = await _backend.friendsActivity();
    // One read per friend in the list, all at once, for the flame state.
    final handles = {for (final a in items) a.actor.handle};
    final hyped = await Future.wait([
      for (final h in handles)
        _backend.myHypesOn(h).then((s) => MapEntry(h, s),
            onError: (Object _) => MapEntry(h, <int>{})),
    ]);
    _hyped
      ..clear()
      ..addEntries(hyped);
    return items;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _feed = next;
    });
    await next;
  }

  Future<void> _toggleHype(ActivityItem a) async {
    final h = a.actor.handle;
    final mine = _hyped.putIfAbsent(h, () => {});
    final next = !mine.contains(a.igdbId);
    setState(() => next ? mine.add(a.igdbId) : mine.remove(a.igdbId));
    try {
      await _backend.setHype(h, a.igdbId, next);
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() => next ? mine.remove(a.igdbId) : mine.add(a.igdbId));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(accountFailureText(e))));
    }
  }

  Future<void> _graft(ActivityItem a) async {
    await graftFromFriend(
      context.read<LudeckStore>(),
      igdbId: a.igdbId,
      title: a.title,
      coverUrl: a.coverUrl,
      fromHandle: a.actor.handle,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Grafted ${a.title} onto your tree. It is on your '
            'wishlist, from @${a.actor.handle}.')));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore?>();
    final owned = {
      for (final i in store?.items ?? const <TreeItem>[]) i.game.igdbId,
    };
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ActivityItem>>(
              future: _feed,
              builder: (context, snap) {
                final items = snap.data;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(Tokens.space.md),
                  children: [
                    Row(children: [
                      BackButton(color: Tokens.palette.text),
                      const AccountTitle('Lately'),
                    ]),
                    SizedBox(height: Tokens.space.md),
                    if (snap.hasError)
                      Text("Couldn't load what friends have been up to.",
                          style: TextStyle(color: Tokens.palette.textDim))
                    else if (items == null)
                      Center(
                          child: CircularProgressIndicator(
                              color: Tokens.palette.textDim))
                    else if (items.isEmpty)
                      Text(
                        'Nothing yet. When friends plant, finish or rate a '
                        'game, it shows up here.',
                        key: const Key('lately-empty'),
                        style: TextStyle(color: Tokens.palette.textDim),
                      )
                    else ...[
                      for (final a in items)
                        _Line(
                          item: a,
                          hyped: _hyped[a.actor.handle]?.contains(a.igdbId) ??
                              false,
                          owned: owned.contains(a.igdbId),
                          onHype: () => _toggleHype(a),
                          onGraft: () => _graft(a),
                        ),
                      SizedBox(height: Tokens.space.lg),
                      Center(
                        child: Text(
                          "That's everything from the last two weeks.",
                          key: const Key('lately-end'),
                          style: TextStyle(
                              color: Tokens.palette.textDim,
                              fontSize: Tokens.type.caption),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.hyped,
    required this.owned,
    required this.onHype,
    required this.onGraft,
  });

  final ActivityItem item;
  final bool hyped;
  final bool owned;
  final VoidCallback onHype;
  final VoidCallback onGraft;

  @override
  Widget build(BuildContext context) {
    final a = item;
    return Padding(
      key: Key('lately-${a.id}'),
      padding: EdgeInsets.only(bottom: Tokens.space.sm),
      child: SoftCard(
        deep: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => VisitScreen(handle: a.actor.handle))),
              child: ProfileOrb(
                  seed: a.actor.avatarSeed, name: a.actor.displayName),
            ),
            SizedBox(width: Tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '@${a.actor.handle} ',
                        style: TextStyle(
                            color: Tokens.palette.text,
                            fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: activitySentence(a),
                        style: TextStyle(color: Tokens.palette.text)),
                  ])),
                  Text(whenLabel(a.at),
                      style: TextStyle(
                          color: Tokens.palette.textDim,
                          fontSize: Tokens.type.caption)),
                  Row(children: [
                    IconButton(
                      key: Key('lately-hype-${a.id}'),
                      tooltip: hyped ? 'Hyped. Tap to undo' : 'Hype ${a.title}',
                      isSelected: hyped,
                      onPressed: onHype,
                      icon: Icon(
                        hyped
                            ? Icons.local_fire_department
                            : Icons.local_fire_department_outlined,
                        color:
                            hyped ? Tokens.palette.text : Tokens.palette.textDim,
                      ),
                    ),
                    owned
                        ? Text('In yours',
                            style: TextStyle(
                                color: Tokens.palette.textDim,
                                fontSize: Tokens.type.caption))
                        : TextButton(
                            key: Key('lately-graft-${a.id}'),
                            onPressed: onGraft,
                            child: const Text('Plant'),
                          ),
                  ]),
                ],
              ),
            ),
            if (a.coverUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radius.card / 2),
                child: Image.network(a.coverUrl!,
                    width: 44,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(width: 44)),
              ),
          ],
        ),
      ),
    );
  }
}
