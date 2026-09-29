// The inbox: games friends sent you, and what happened to you socially.
//
// A seed waits here until you plant it or say it is not for you. Planting
// grafts it onto your tree as a wishlist game "from @them", which is what
// lands it in the soil strip with who sent it. Notifications are written by
// the server alone (0003), so nothing here can be forged by another app.
//
// Opening the inbox marks everything read. The unread number is shown only to
// you, as a dot and a count on your own Settings row, never to anyone else.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../account/account_widgets.dart';
import '../friends/friends_screen.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';
import 'graft.dart';
import 'lately_screen.dart' show whenLabel;

typedef _Inbox = ({
  List<Recommendation> seeds,
  List<SocialNotification> notes,
});

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late Future<_Inbox> _inbox;

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    _inbox = _load();
  }

  Future<_Inbox> _load() async {
    final r = await Future.wait<Object>([
      _backend.recommendationsInbox(),
      _backend.notifications(),
    ]);
    final inbox = (
      seeds: [
        for (final s in r[0] as List<Recommendation>)
          if (s.status == RecommendationStatus.sent) s,
      ],
      notes: r[1] as List<SocialNotification>,
    );
    // Seen now. The dots in this list still show what was new on arrival.
    try {
      await _backend.markNotificationsRead();
    } on SocialException {
      // They stay unread; nothing else depends on it.
    }
    return inbox;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _inbox = next;
    });
    await next;
  }

  Future<void> _plant(Recommendation s) async {
    final store = context.read<LudeckStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _backend.setRecommendationStatus(s.id, RecommendationStatus.planted);
      await graftFromFriend(
        store,
        igdbId: s.igdbId,
        title: s.title,
        coverUrl: s.coverUrl,
        fromHandle: s.from.handle,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('Planted ${s.title}. It is on your wishlist, from '
              '@${s.from.handle}.')));
    } on SocialException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(accountFailureText(e))));
    }
    if (mounted) await _refresh();
  }

  Future<void> _dismiss(Recommendation s) async {
    try {
      await _backend.setRecommendationStatus(
          s.id, RecommendationStatus.dismissed);
    } on SocialException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(accountFailureText(e))));
      }
    }
    if (mounted) await _refresh();
  }

  void _open(SocialNotification n) {
    final screen = n.kind == NotificationKind.followRequest
        ? const FriendsScreen()
        : VisitScreen(handle: n.actor.handle);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CosmosBackdrop(
          sky: Sky.deep,
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<_Inbox>(
                future: _inbox,
                builder: (context, snap) {
                  final inbox = snap.data;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(Tokens.space.md),
                    children: [
                      Row(children: [
                        BackButton(color: Tokens.palette.text),
                        const AccountTitle('Inbox'),
                      ]),
                      SizedBox(height: Tokens.space.md),
                      if (snap.hasError)
                        Text("Couldn't load your inbox just now.",
                            style: TextStyle(color: Tokens.palette.textDim))
                      else if (inbox == null)
                        Center(
                            child: CircularProgressIndicator(
                                color: Tokens.palette.textDim))
                      else ...[
                        if (inbox.seeds.isNotEmpty) ...[
                          _heading('Sent to you'),
                          for (final s in inbox.seeds)
                            _SeedCard(
                              seed: s,
                              onPlant: () => _plant(s),
                              onDismiss: () => _dismiss(s),
                            ),
                          SizedBox(height: Tokens.space.md),
                        ],
                        _heading('Activity'),
                        if (inbox.notes.isEmpty)
                          Text(
                            'Follows, hypes and games friends send you show '
                            'up here.',
                            key: const Key('inbox-empty'),
                            style: TextStyle(color: Tokens.palette.textDim),
                          )
                        else
                          for (final n in inbox.notes)
                            _NoteRow(note: n, onTap: () => _open(n)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

  Widget _heading(String text) => Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: Text(text,
            style: TextStyle(
                color: Tokens.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: Tokens.type.body)),
      );
}

class _SeedCard extends StatelessWidget {
  const _SeedCard(
      {required this.seed, required this.onPlant, required this.onDismiss});

  final Recommendation seed;
  final VoidCallback onPlant;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = seed;
    return Padding(
      key: Key('seed-${s.id}'),
      padding: EdgeInsets.only(bottom: Tokens.space.sm),
      child: SoftCard(
        deep: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radius.card / 2),
              child: SizedBox(
                width: 48,
                height: 64,
                child: s.coverUrl == null
                    ? ColoredBox(color: Tokens.palette.surface)
                    : Image.network(s.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: Tokens.palette.surface)),
              ),
            ),
            SizedBox(width: Tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      style: TextStyle(
                          color: Tokens.palette.text,
                          fontWeight: FontWeight.w600)),
                  Text('From @${s.from.handle}, ${whenLabel(s.at)}',
                      style: TextStyle(
                          color: Tokens.palette.textDim,
                          fontSize: Tokens.type.caption)),
                  if (s.message.isNotEmpty) ...[
                    SizedBox(height: Tokens.space.xxs),
                    Text(s.message,
                        key: Key('seed-message-${s.id}'),
                        style: TextStyle(color: Tokens.palette.text)),
                  ],
                  SizedBox(height: Tokens.space.xs),
                  Wrap(spacing: Tokens.space.xs, children: [
                    FilledButton(
                      key: Key('seed-plant-${s.id}'),
                      onPressed: onPlant,
                      style: FilledButton.styleFrom(
                        backgroundColor: Tokens.palette.accent,
                        foregroundColor: Tokens.palette.bg,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Plant it'),
                    ),
                    TextButton(
                      key: Key('seed-dismiss-${s.id}'),
                      onPressed: onDismiss,
                      child: const Text('Not for me'),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.onTap});

  final SocialNotification note;
  final VoidCallback onTap;

  String get _text => switch (note.kind) {
        NotificationKind.follow => 'started following you',
        NotificationKind.followRequest => 'asked to follow you',
        NotificationKind.followAccepted => 'accepted your request',
        NotificationKind.recommendation => 'sent you a game',
        NotificationKind.hype => 'hyped a game on your tree',
      };

  IconData get _icon => switch (note.kind) {
        NotificationKind.follow ||
        NotificationKind.followAccepted =>
          Icons.person_add_alt_1_outlined,
        NotificationKind.followRequest => Icons.lock_open_outlined,
        NotificationKind.recommendation => Icons.spa_outlined,
        NotificationKind.hype => Icons.local_fire_department_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final n = note;
    return ListTile(
      key: Key('note-${n.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ProfileOrb(seed: n.actor.avatarSeed, name: n.actor.displayName),
      title: Text.rich(TextSpan(children: [
        TextSpan(
            text: '@${n.actor.handle} ',
            style: TextStyle(
                color: Tokens.palette.text, fontWeight: FontWeight.w600)),
        TextSpan(text: _text, style: TextStyle(color: Tokens.palette.text)),
      ])),
      subtitle: Text(whenLabel(n.at),
          style: TextStyle(
              color: Tokens.palette.textDim, fontSize: Tokens.type.caption)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (n.isUnread)
          Semantics(
            label: 'New',
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Tokens.palette.text),
            ),
          ),
        SizedBox(width: Tokens.space.xs),
        Icon(_icon, color: Tokens.palette.textDim),
      ]),
    );
  }
}
