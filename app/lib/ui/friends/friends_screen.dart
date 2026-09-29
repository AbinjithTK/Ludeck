// Friends: find people, see who you follow and who follows you, answer
// requests, and invite someone new.
//
// The frozen decision in docs/DECISIONS.md ("a friends list with handle
// search... no counts, no feed") still shapes this screen: the lists are
// lists, not scores. Tabs name the list, never how long it is. The quiet feed
// (direction B, 2026-09-29) lives in its own place, not here.
//
// Search works signed out, because finding someone's orchard never needed an
// account. Following does; the button asks for one when it has to.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../account/account_flow.dart';
import '../account/account_widgets.dart';
import '../gamified/primitives.dart';
import '../social/inbox_screen.dart';
import '../social/lately_screen.dart';
import '../tokens.dart';
import 'invite_sheet.dart';
import 'people_widgets.dart';

enum _Tab { friends, following, followers }

typedef _Graph = ({
  List<SocialPerson> following,
  List<SocialPerson> followers,
  List<SocialPerson> requests,
});

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<SocialPerson>? _results;
  bool _searching = false;
  String? _searchError;

  _Tab _tab = _Tab.friends;
  Future<_Graph>? _graph;

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    final b = _backend;
    setState(() {
      _graph = b.currentProfile == null
          ? null
          : () async {
              final r = await Future.wait([
                b.followingPeople(),
                b.followers(),
                b.followRequests(),
              ]);
              return (following: r[0], followers: r[1], requests: r[2]);
            }();
    });
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (normalizeHandle(q).length < 2) {
      setState(() {
        _results = null;
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() => _searching = true);
    final seq = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _backend.searchPeople(q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = r;
          _searching = false;
          _searchError = null;
        });
      } on SocialException catch (e) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _searching = false;
          _searchError = accountFailureText(e);
        });
      }
    });
  }

  Future<void> _invite() async {
    final me = await ensureAccount(context);
    if (me == null || !mounted) return;
    _reload();
    await showInviteSheet(context, me);
  }

  Future<void> _signIn() async {
    await ensureAccount(context);
    if (mounted) _reload();
  }

  Future<void> _respond(SocialPerson p, bool accept) async {
    try {
      await _backend.respondToFollowRequest(p.handle, accept: accept);
    } on SocialException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(accountFailureText(e))));
      }
    }
    if (mounted) _reload();
  }

  void _changed(SocialPerson _) => _reload();

  @override
  Widget build(BuildContext context) {
    final signedIn = _backend.currentProfile != null;
    final query = _search.text;
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(Tokens.space.md),
            children: [
              Row(children: [
                if (Navigator.of(context).canPop())
                  BackButton(color: Tokens.palette.text),
                const Expanded(child: AccountTitle('Friends')),
                if (signedIn) ...[
                  IconButton(
                    key: const Key('friends-lately'),
                    tooltip: 'Lately',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const LatelyScreen())),
                    icon: Icon(Icons.local_florist_outlined,
                        color: Tokens.palette.text),
                  ),
                  IconButton(
                    key: const Key('friends-inbox'),
                    tooltip: 'Inbox',
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(
                            builder: (_) => const InboxScreen()))
                        .then((_) => _reload()),
                    icon:
                        Icon(Icons.inbox_outlined, color: Tokens.palette.text),
                  ),
                ],
                IconButton(
                  key: const Key('friends-invite'),
                  tooltip: 'Invite a friend',
                  onPressed: _invite,
                  icon: Icon(Icons.qr_code_rounded, color: Tokens.palette.text),
                ),
              ]),
              SizedBox(height: Tokens.space.sm),
              TextField(
                key: const Key('friends-search'),
                controller: _search,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: _onQuery,
                style: TextStyle(color: Tokens.palette.text),
                decoration: accountField(
                  hint: 'Search by ID or name',
                  prefix: '@',
                  suffix: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: Icon(Icons.close, color: Tokens.palette.textDim),
                          onPressed: () {
                            _search.clear();
                            _onQuery('');
                          },
                        ),
                ),
              ),
              SizedBox(height: Tokens.space.md),
              if (normalizeHandle(query).length >= 2)
                ..._searchResults()
              else if (!signedIn)
                _signedOutCard()
              else
                _lists(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchResults() {
    if (_searchError != null) {
      return [Text(_searchError!, style: TextStyle(color: Tokens.palette.danger))];
    }
    final r = _results;
    if (r == null || _searching && r.isEmpty) {
      return [
        Center(child: CircularProgressIndicator(color: Tokens.palette.textDim)),
      ];
    }
    if (r.isEmpty) {
      return [
        Text('Nobody by that ID or name yet.',
            key: const Key('friends-no-results'),
            style: TextStyle(color: Tokens.palette.textDim)),
        SizedBox(height: Tokens.space.sm),
        OutlinedButton.icon(
          onPressed: _invite,
          icon: const Icon(Icons.qr_code_rounded),
          label: const Text('Invite them instead'),
        ),
      ];
    }
    return [
      for (final p in r)
        PersonRow(key: Key('result-${p.handle}'), person: p, onChanged: _changed),
    ];
  }

  Widget _signedOutCard() => SoftCard(
        deep: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign in to follow people and keep your friends here.',
                style: TextStyle(color: Tokens.palette.text)),
            SizedBox(height: Tokens.space.xs),
            Text("You can still search and open anyone's public orchard.",
                style: TextStyle(
                    color: Tokens.palette.textDim,
                    fontSize: Tokens.type.caption)),
            SizedBox(height: Tokens.space.sm),
            FilledButton(
              key: const Key('friends-sign-in'),
              onPressed: _signIn,
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.palette.accent,
                foregroundColor: Tokens.palette.bg,
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );

  Widget _lists() => FutureBuilder<_Graph>(
        future: _graph,
        builder: (context, snap) {
          if (snap.hasError) {
            return Column(children: [
              Text("Couldn't load your friends just now.",
                  style: TextStyle(color: Tokens.palette.textDim)),
              TextButton(onPressed: _reload, child: const Text('Try again')),
            ]);
          }
          final g = snap.data;
          if (g == null) {
            return Center(
                child: CircularProgressIndicator(color: Tokens.palette.textDim));
          }
          final list = switch (_tab) {
            _Tab.friends => [for (final p in g.following) if (p.isFriend) p],
            _Tab.following => g.following,
            _Tab.followers => g.followers,
          };
          final empty = switch (_tab) {
            _Tab.friends =>
              'Friends are people you follow who follow you back. Search for '
                  'someone, or invite them.',
            _Tab.following => "You aren't following anyone yet.",
            _Tab.followers => 'Nobody follows you yet. Share your invite link.',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (g.requests.isNotEmpty) ...[
                Text('Asking to follow you',
                    style: TextStyle(
                        color: Tokens.palette.text,
                        fontWeight: FontWeight.w600)),
                for (final p in g.requests)
                  PersonRow(
                    key: Key('request-${p.handle}'),
                    person: p,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        key: Key('decline-${p.handle}'),
                        tooltip: 'Decline',
                        onPressed: () => _respond(p, false),
                        icon: Icon(Icons.close, color: Tokens.palette.textDim),
                      ),
                      FilledButton(
                        key: Key('accept-${p.handle}'),
                        onPressed: () => _respond(p, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.palette.text,
                          foregroundColor: Tokens.palette.bg,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Accept'),
                      ),
                    ]),
                  ),
                SizedBox(height: Tokens.space.md),
              ],
              SegmentedButton<_Tab>(
                key: const Key('friends-tabs'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Tab.friends, label: Text('Friends')),
                  ButtonSegment(value: _Tab.following, label: Text('Following')),
                  ButtonSegment(value: _Tab.followers, label: Text('Followers')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              SizedBox(height: Tokens.space.sm),
              if (list.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: Tokens.space.md),
                  child: Text(empty,
                      key: const Key('friends-empty'),
                      style: TextStyle(color: Tokens.palette.textDim)),
                )
              else
                for (final p in list) PersonRow(person: p, onChanged: _changed),
            ],
          );
        },
      );
}
