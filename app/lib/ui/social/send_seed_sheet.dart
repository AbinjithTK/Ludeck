// Send a game to a friend: it lands in their inbox as a seed "from @you".
//
// Only people who follow you can receive one (0003 `may_recommend_to`), so a
// stranger cannot fill someone's inbox. The picker therefore lists your
// followers, friends first, and says plainly when there is nobody yet.
//
// PRIVACY -- invariant 10. The seed carries the game's id, title and cover,
// and the short line you type. Your note on the game and who recommended it
// to you stay on this phone.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/social/social_backend.dart';
import '../account/account_flow.dart';
import '../account/account_widgets.dart';
import '../tokens.dart';

Future<void> showSendSeedSheet(BuildContext context, Game game) async {
  final backend = context.read<SocialBackend>();
  if (backend.currentProfile == null && await ensureAccount(context) == null) {
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Provider<SocialBackend>.value(
      value: backend,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _SendSheet(game: game),
      ),
    ),
  );
}

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.game});

  final Game game;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late final Future<List<SocialPerson>> _people;
  final _message = TextEditingController();
  final Set<String> _to = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _people = context.read<SocialBackend>().followers().then((list) =>
        [...list]..sort((a, b) {
            // Friends first, then by name.
            if (a.isFriend != b.isFriend) return a.isFriend ? -1 : 1;
            return a.profile.displayName
                .toLowerCase()
                .compareTo(b.profile.displayName.toLowerCase());
          }));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_to.isEmpty) {
      setState(() => _error = 'Pick who to send it to.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final backend = context.read<SocialBackend>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sent = <String>[];
    try {
      for (final h in _to) {
        await backend.recommend(
          toHandle: h,
          igdbId: widget.game.igdbId,
          title: widget.game.title,
          coverUrl: widget.game.coverUrl,
          message: _message.text.trim(),
        );
        sent.add(h);
      }
      messenger?.showSnackBar(SnackBar(
          content: Text(sent.length == 1
              ? 'Sent ${widget.game.title} to @${sent.single}.'
              : 'Sent ${widget.game.title} to ${sent.length} friends.')));
      nav.pop();
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.failure == SocialFailure.forbidden
            ? 'They need to follow you before you can send them games.'
            : accountFailureText(e);
        _to.removeAll(sent);
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              Tokens.space.lg, 0, Tokens.space.lg, Tokens.space.lg),
          child: Column(
            key: const Key('send-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountTitle('Send ${widget.game.title}',
                  body: 'It lands in their inbox, from you. Your notes stay '
                      'on this phone.'),
              SizedBox(height: Tokens.space.md),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: FutureBuilder<List<SocialPerson>>(
                  future: _people,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text("Couldn't load your friends just now.",
                          style: TextStyle(color: Tokens.palette.textDim));
                    }
                    final people = snap.data;
                    if (people == null) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: Tokens.palette.textDim));
                    }
                    if (people.isEmpty) {
                      return Text(
                        'Only people who follow you can get games from you. '
                        'Invite someone from Friends.',
                        key: const Key('send-empty'),
                        style: TextStyle(color: Tokens.palette.textDim),
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in people)
                          CheckboxListTile(
                            key: Key('send-to-${p.handle}'),
                            contentPadding: EdgeInsets.zero,
                            value: _to.contains(p.handle),
                            onChanged: _busy
                                ? null
                                : (on) => setState(() => on == true
                                    ? _to.add(p.handle)
                                    : _to.remove(p.handle)),
                            secondary: ProfileOrb(
                                seed: p.profile.avatarSeed,
                                name: p.profile.displayName),
                            title: Text(p.profile.displayName,
                                style: TextStyle(color: Tokens.palette.text)),
                            subtitle: Text(
                                p.isFriend
                                    ? '@${p.handle}, friends'
                                    : '@${p.handle}',
                                style:
                                    TextStyle(color: Tokens.palette.textDim)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: Tokens.space.sm),
              TextField(
                key: const Key('send-message'),
                controller: _message,
                maxLength: 140,
                style: TextStyle(color: Tokens.palette.text),
                decoration: accountField(hint: 'Add a line (optional)'),
              ),
              if (_error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      key: const Key('send-error'),
                      style: TextStyle(color: Tokens.palette.danger)),
                ),
                SizedBox(height: Tokens.space.xs),
              ],
              FilledButton.icon(
                key: const Key('send-go'),
                onPressed: _busy ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: Tokens.palette.accent,
                  foregroundColor: Tokens.palette.bg,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      );
}
