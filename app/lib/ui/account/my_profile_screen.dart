// Your profile, as friends see it, plus the numbers only you see.
//
// The orchard comes first because the tree is the avatar. Below it: who you
// are, what you play on, what this season holds, and the games friends hyped.
//
// Follower and following numbers appear here and nowhere else. They are
// shown to you, on your own page, as a way into the lists; nobody else is
// shown them, on your page or theirs. That keeps DECISIONS.md's "no counts"
// true for everything public (2026-09-29, direction B), which is the point:
// the orchard is never a scoreboard.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/season.dart';
import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../gamified/primitives.dart';
import '../orchard/orchard_portrait.dart';
import '../profile/profile_screen.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';
import 'account_settings_screen.dart';
import 'account_widgets.dart';
import 'profile_fields.dart';

/// What the page loads from the server, all at once.
typedef _Social = ({
  List<SocialPerson> followers,
  List<SocialPerson> following,
  List<Hype> hypes,
});

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, this.hero});

  /// The orchard picture. Defaults to the store-backed portrait; a test
  /// passes a plain box so no canvas is needed.
  final Widget? hero;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<_Social> _social;

  @override
  void initState() {
    super.initState();
    _social = _load();
  }

  Future<_Social> _load() async {
    final b = context.read<SocialBackend>();
    final r = await Future.wait<Object>([
      b.followers(),
      b.followingPeople(),
      b.hypesOnMyTree(),
    ]);
    return (
      followers: r[0] as List<SocialPerson>,
      following: r[1] as List<SocialPerson>,
      hypes: r[2] as List<Hype>,
    );
  }

  void _openList(String title, List<SocialPerson> people, String empty) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PeopleListScreen(
          title: title,
          load: () async => [for (final p in people) p.profile],
          empty: empty,
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final me = context.read<SocialBackend>().currentProfile;
    final store = context.watch<LudeckStore?>();
    final items = store?.items ?? const <TreeItem>[];
    if (me == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final season = summarise(items);
    final hero = widget.hero ??
        (store == null
            ? const SizedBox.shrink()
            : OrchardPortrait(trees: ProfileScreen.portraitTrees(store, items)));

    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.only(bottom: Tokens.space.xl),
            children: [
              Row(children: [BackButton(color: Tokens.palette.text)]),
              SizedBox(height: 220, child: hero),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Tokens.space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      ProfileOrb(
                          seed: me.avatarSeed, name: me.displayName, diameter: 56),
                      SizedBox(width: Tokens.space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(me.displayName,
                                style: TextStyle(
                                    fontFamily: Tokens.type.displayFamily,
                                    fontSize: Tokens.type.title,
                                    fontWeight: FontWeight.w700,
                                    color: Tokens.palette.text)),
                            Row(children: [
                              Text('@${me.handle}',
                                  style:
                                      TextStyle(color: Tokens.palette.textDim)),
                              if (me.isPrivate) ...[
                                SizedBox(width: Tokens.space.xxs),
                                Icon(Icons.lock_outline,
                                    size: 14, color: Tokens.palette.textDim),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ]),
                    if (me.bio.isNotEmpty) ...[
                      SizedBox(height: Tokens.space.sm),
                      Text(me.bio, style: TextStyle(color: Tokens.palette.text)),
                    ],
                    if (me.platforms.isNotEmpty) ...[
                      SizedBox(height: Tokens.space.sm),
                      Wrap(
                        spacing: Tokens.space.xs,
                        runSpacing: Tokens.space.xs,
                        children: [
                          for (final p in me.platforms)
                            Chip(label: Text(platformLabels[p] ?? p)),
                        ],
                      ),
                    ],
                    SizedBox(height: Tokens.space.md),
                    FutureBuilder<_Social>(
                      future: _social,
                      builder: (context, snap) {
                        final s = snap.data;
                        if (snap.hasError) {
                          return Text("Couldn't load your friends just now.",
                              style: TextStyle(color: Tokens.palette.textDim));
                        }
                        if (s == null) {
                          return SizedBox(
                            height: 40,
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: Tokens.palette.textDim)),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _Count(
                                key: const Key('profile-followers'),
                                n: s.followers.length,
                                word: s.followers.length == 1
                                    ? 'follower'
                                    : 'followers',
                                onTap: () => _openList(
                                    'Followers',
                                    s.followers,
                                    'Nobody follows you yet.'),
                              ),
                              SizedBox(width: Tokens.space.lg),
                              _Count(
                                key: const Key('profile-following'),
                                n: s.following.length,
                                word: 'following',
                                onTap: () => _openList(
                                    'Following',
                                    s.following,
                                    "You aren't following anyone yet."),
                              ),
                            ]),
                            Text('Only you see these numbers.',
                                style: TextStyle(
                                    color: Tokens.palette.textDim,
                                    fontSize: Tokens.type.caption)),
                            SizedBox(height: Tokens.space.lg),
                            _Hyped(hypes: s.hypes, items: items),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: Tokens.space.lg),
                    _Heading('This season'),
                    Wrap(
                      spacing: Tokens.space.lg,
                      runSpacing: Tokens.space.sm,
                      children: [
                        _Stat(n: season.harvested, word: 'Finished'),
                        _Stat(n: season.stillGrowing, word: 'To play'),
                        _Stat(n: season.seeds, word: 'Wishlist'),
                        _Stat(n: store?.branches.length ?? 0, word: 'Trees'),
                      ],
                    ),
                    SizedBox(height: Tokens.space.lg),
                    OutlinedButton.icon(
                      key: const Key('profile-as-visitor'),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => VisitScreen(handle: me.handle))),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('See it as a visitor'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.sm),
        child: Text(text,
            style: TextStyle(
                fontFamily: Tokens.type.displayFamily,
                fontWeight: FontWeight.w700,
                fontSize: Tokens.type.body,
                color: Tokens.palette.text)),
      );
}

class _Count extends StatelessWidget {
  const _Count(
      {super.key, required this.n, required this.word, required this.onTap});

  final int n;
  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$n $word',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$n ',
                  style: TextStyle(
                      color: Tokens.palette.text, fontWeight: FontWeight.w700)),
              TextSpan(
                  text: word, style: TextStyle(color: Tokens.palette.textDim)),
            ])),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.n, required this.word});

  final int n;
  final String word;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n',
              style: TextStyle(
                  fontFamily: Tokens.type.displayFamily,
                  fontSize: Tokens.type.title,
                  fontWeight: FontWeight.w700,
                  color: Tokens.palette.text)),
          Text(word,
              style: TextStyle(
                  color: Tokens.palette.textDim, fontSize: Tokens.type.caption)),
        ],
      );
}

/// Your games that friends hyped, with who. Grouped by game, newest first.
class _Hyped extends StatelessWidget {
  const _Hyped({required this.hypes, required this.items});

  final List<Hype> hypes;
  final List<TreeItem> items;

  @override
  Widget build(BuildContext context) {
    final byGame = <int, List<SocialProfile>>{};
    for (final h in hypes) {
      byGame.putIfAbsent(h.igdbId, () => []).add(h.from);
    }
    final games = {for (final i in items) i.game.igdbId: i.game};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Hyped by friends'),
        if (byGame.isEmpty)
          Text('When a friend hypes one of your games, it shows up here.',
              key: const Key('profile-hyped-empty'),
              style: TextStyle(color: Tokens.palette.textDim))
        else
          for (final e in byGame.entries)
            Padding(
              key: Key('profile-hyped-${e.key}'),
              padding: EdgeInsets.only(bottom: Tokens.space.sm),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radius.card / 2),
                  child: SizedBox(
                    width: 40,
                    height: 54,
                    child: games[e.key]?.coverUrl == null
                        ? ColoredBox(color: Tokens.palette.surface)
                        : Image.network(games[e.key]!.coverUrl!,
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
                      Text(games[e.key]?.title ?? 'A game you no longer track',
                          style: TextStyle(color: Tokens.palette.text)),
                      Text(
                        _names(e.value),
                        style: TextStyle(
                            color: Tokens.palette.textDim,
                            fontSize: Tokens.type.caption),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
      ],
    );
  }

  static String _names(List<SocialProfile> people) {
    final names = [for (final p in people) '@${p.handle}'];
    if (names.length <= 2) return 'Hyped by ${names.join(' and ')}';
    return 'Hyped by ${names.take(2).join(', ')} and ${names.length - 2} more';
  }
}
