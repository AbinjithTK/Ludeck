// Visiting: docs/DESIGN.md section 6, "Social: visiting, not competing".
//
// "Visit a friend's tree. Read-only. See their branches, their harvests." and
// "Plant from a friend's tree. One tap moves a fruit you saw into your soil as
// a seed, crediting them. This is the loop: a visit produces a capture." This
// screen is those two verbs plus who the person is: their ID, a Friends badge
// when you follow each other, a few numbers about their season, and the games
// of theirs you hyped.
//
// No public counts (DECISIONS.md, direction B, 2026-09-29). A visitor sees
// which reactions THEY gave, highlighted; only the owner, looking at their own
// tree, sees how many. A hype is between the two of you.
//
// A friends-only orchard you may not see yet looks like a closed gate, with
// the person's name on it and a button to ask, rather than "not found".
//
// docs/DESIGN.md section 9: visiting is free forever, never paywalled -- this
// screen carries no entitlement check.
//
// PRIVACY: this screen renders exactly what SocialBackend.treeByHandle returns,
// which is PublishedTree/PublishedGame -- the same privacy-safe shape publish
// used to send it. There is no code path here back to the owner's private
// recommendedBy/note/channel; those never left their device in the first place.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account/account_flow.dart';
import '../account/account_widgets.dart';
import '../account/profile_fields.dart';
import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../friends/people_widgets.dart';
import '../gamified/primitives.dart';
import '../social/graft.dart';
import '../tokens.dart';

/// The visit route. Takes a HANDLE, not a whole tree -- the caller (a shared
/// link, a search result) only ever has the handle, and this screen owns
/// fetching from there. Reads the backend from Provider like every other
/// social screen.
class VisitScreen extends StatefulWidget {
  const VisitScreen({super.key, required this.handle});

  final String handle;

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  late Future<PublishedTree> _future;

  /// Who they are and how you relate. Null until loaded, and stays null when
  /// it cannot be read (offline); the tree still shows.
  SocialPerson? _person;

  // Reaction and hype state is read separately from the tree itself: reacting
  // does not change what the tree contains, so re-fetching the whole tree on
  // every tap would be wasted work and would also flicker every row while it
  // reloads. Loaded once alongside the tree, updated locally after a write.
  List<TreeReaction> _reactions = const [];
  Set<int> _hyped = const {};
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final backend = context.read<SocialBackend>();
    _future = backend.treeByHandle(widget.handle);
    _loadPerson(backend);
    _loadReactionsAndHypes(backend);
  }

  Future<void> _loadPerson(SocialBackend backend) async {
    try {
      final p = await backend.personByHandle(widget.handle);
      if (mounted) setState(() => _person = p);
    } on SocialException {
      // An unknown handle is already shown by the tree's own notFound.
    }
  }

  Future<void> _loadReactionsAndHypes(SocialBackend backend) async {
    try {
      final reactions = await backend.reactionsFor(widget.handle);
      // Hypes need sign-in; a signed-out visitor simply has none.
      final hyped = backend.currentProfile == null
          ? const <int>{}
          : await backend.myHypesOn(widget.handle);
      if (!mounted) return;
      setState(() {
        _reactions = reactions;
        _hyped = hyped;
      });
    } on SocialException {
      // Failing to load these should not block the tree itself from
      // rendering; everything simply starts unselected.
    }
  }

  SocialProfile? get _me => context.read<SocialBackend>().currentProfile;

  bool get _isMine => _me?.handle == widget.handle;

  Future<bool> _needAccount() async {
    if (_me != null) return true;
    final p = await ensureAccount(context);
    if (p != null && mounted) {
      // Now signed in: relationship and hypes may have changed.
      _loadPerson(context.read<SocialBackend>());
      _loadReactionsAndHypes(context.read<SocialBackend>());
    }
    return p != null;
  }

  Future<void> _react(ReactionKind kind) async {
    final backend = context.read<SocialBackend>();
    setState(() => _actionInFlight = true);
    try {
      if (!await _needAccount()) {
        if (mounted) setState(() => _actionInFlight = false);
        return;
      }
      await backend.react(widget.handle, kind);
      final reactions = await backend.reactionsFor(widget.handle);
      if (!mounted) return;
      setState(() {
        _reactions = reactions;
        _actionInFlight = false;
      });
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() => _actionInFlight = false);
      _showError(e);
    }
  }

  Future<void> _toggleHype(PublishedGame game) async {
    final backend = context.read<SocialBackend>();
    if (!await _needAccount() || !mounted) return;
    final next = !_hyped.contains(game.igdbId);
    setState(() => _hyped = next
        ? {..._hyped, game.igdbId}
        : ({..._hyped}..remove(game.igdbId)));
    try {
      await backend.setHype(widget.handle, game.igdbId, next);
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() => _hyped = next
          ? ({..._hyped}..remove(game.igdbId))
          : {..._hyped, game.igdbId});
      _showError(e);
    }
  }

  void _showError(SocialException e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.failure == SocialFailure.notConfigured
            ? "Sharing isn't set up yet on this build."
            : 'Something went wrong. Try again.'),
        backgroundColor: Tokens.cosmos.panelDeep,
      ),
    );
  }

  Future<void> _plant(PublishedGame game) async {
    // A graft: into your wishlist, crediting them (ui/social/graft.dart).
    await graftFromFriend(
      context.read<LudeckStore>(),
      igdbId: game.igdbId,
      title: game.title,
      coverUrl: game.coverUrl,
      fromHandle: widget.handle,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Grafted ${game.title} onto your tree. It is on your '
            'wishlist, from @${widget.handle}.'),
        backgroundColor: Tokens.cosmos.panelDeep,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Which of their games are already yours, so Plant says so instead of
    // planting twice. Read-only: a missing store (a bare test) means none.
    final store = context.watch<LudeckStore?>();
    final owned = {
      for (final i in store?.items ?? const <TreeItem>[]) i.game.igdbId,
    };
    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      appBar: AppBar(
        backgroundColor: Tokens.palette.bg,
        foregroundColor: Tokens.palette.text,
        title: Text(
          '@${widget.handle}\'s tree',
          style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
        ),
        actions: [
          if (!_isMine && _person != null)
            _SafetyMenu(handle: widget.handle, person: _person!),
        ],
      ),
      body: CosmosBackdrop(
        child: SafeArea(
          child: FutureBuilder<PublishedTree>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final p = _person;
                final gated = p != null &&
                    p.profile.isPrivate &&
                    p.iFollow != FollowState.accepted;
                if (gated) {
                  return _Gate(
                    person: p,
                    onChanged: (next) => setState(() => _person = next),
                  );
                }
                return _VisitError(error: snapshot.error, handle: widget.handle);
              }
              final me = _me;
              return _VisitBody(
                tree: snapshot.data!,
                person: _person,
                isMine: _isMine,
                onPlant: _plant,
                owned: owned,
                hyped: _hyped,
                onHype: _isMine ? null : _toggleHype,
                reactions: _reactions,
                myId: me?.id,
                actionsEnabled: !_actionInFlight,
                onReact: _react,
                onPersonChanged: (next) => setState(() => _person = next),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Block and report, from the app bar. Kept out of the way on purpose: they
/// are rare and serious, not everyday controls.
class _SafetyMenu extends StatelessWidget {
  const _SafetyMenu({required this.handle, required this.person});

  final String handle;
  final SocialPerson person;

  Future<void> _block(BuildContext context) async {
    final backend = context.read<SocialBackend>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Block @$handle?'),
        content: const Text(
            "You stop following each other. They can't find you, see your "
            "tree or send you games, and they aren't told. You can unblock "
            'them in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          TextButton(
            key: const Key('confirm-block'),
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: Tokens.palette.danger),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (backend.currentProfile == null) return;
    try {
      await backend.block(handle);
      messenger.showSnackBar(SnackBar(content: Text('Blocked @$handle.')));
      nav.pop();
    } on SocialException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(accountFailureText(e))));
    }
  }

  Future<void> _report(BuildContext context) async {
    final backend = context.read<SocialBackend>();
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Report @$handle'),
        children: [
          for (final r in ReportReason.values)
            SimpleDialogOption(
              key: Key('report-${r.name}'),
              onPressed: () => Navigator.of(c).pop(r),
              child: Text(switch (r) {
                ReportReason.spam => 'Spam',
                ReportReason.harassment => 'Harassment',
                ReportReason.impersonation => 'Pretending to be someone',
                ReportReason.inappropriate => 'Inappropriate profile',
                ReportReason.other => 'Something else',
              }),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await backend.report(handle, reason);
      messenger.showSnackBar(const SnackBar(
          content: Text('Thanks. We will look at it. They are not told.')));
    } on SocialException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(accountFailureText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.read<SocialBackend>().currentProfile == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      key: const Key('visit-menu'),
      tooltip: 'More',
      onSelected: (v) => v == 'block' ? _block(context) : _report(context),
      itemBuilder: (_) => const [
        PopupMenuItem(
            key: Key('visit-report'), value: 'report', child: Text('Report')),
        PopupMenuItem(
            key: Key('visit-block'), value: 'block', child: Text('Block')),
      ],
    );
  }
}

/// A friends-only orchard you cannot see yet.
class _Gate extends StatelessWidget {
  const _Gate({required this.person, required this.onChanged});

  final SocialPerson person;
  final ValueChanged<SocialPerson> onChanged;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.all(Tokens.space.md),
        children: [
          _PersonHeader(person: person, isMine: false, onChanged: onChanged),
          SizedBox(height: Tokens.space.lg),
          SoftCard(
            deep: true,
            child: Column(children: [
              Icon(Icons.lock_outline, color: Tokens.palette.textDim),
              SizedBox(height: Tokens.space.xs),
              Text(
                person.iFollow == FollowState.pending
                    ? 'You asked to follow. Their orchard opens when they say '
                        'yes.'
                    : 'This orchard is friends only. Ask to follow and they '
                        'can let you in.',
                key: const Key('visit-gate'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Tokens.palette.textDim),
              ),
            ]),
          ),
        ],
      );
}

class _VisitError extends StatelessWidget {
  const _VisitError({required this.error, required this.handle});

  final Object? error;
  final String handle;

  @override
  Widget build(BuildContext context) {
    final notFound =
        error is SocialException && (error as SocialException).failure == SocialFailure.notFound;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Tokens.space.lg),
        child: SoftCard(
          deep: true,
          child: Text(
            notFound
                ? "@$handle's tree isn't public, or doesn't exist."
                : "Couldn't load this tree. Try again later.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.palette.textDim, fontSize: Tokens.type.body),
          ),
        ),
      ),
    );
  }
}

/// Who the person is: orb, name, ID, relation, bio, platforms, and follow.
class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.person,
    required this.isMine,
    required this.onChanged,
  });

  final SocialPerson person;
  final bool isMine;
  final ValueChanged<SocialPerson> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = person.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          ProfileOrb(seed: p.avatarSeed, name: p.displayName, diameter: 56),
          SizedBox(width: Tokens.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName,
                    style: TextStyle(
                      fontFamily: Tokens.type.displayFamily,
                      fontSize: Tokens.type.title,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.text,
                    )),
                Wrap(
                  spacing: Tokens.space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('@${p.handle}',
                        style: TextStyle(color: Tokens.palette.textDim)),
                    RelationBadge(person: person),
                  ],
                ),
              ],
            ),
          ),
          if (!isMine) FollowButton(person: person, onChanged: onChanged),
        ]),
        if (p.bio.isNotEmpty) ...[
          SizedBox(height: Tokens.space.sm),
          Text(p.bio, style: TextStyle(color: Tokens.palette.text)),
        ],
        if (p.platforms.isNotEmpty) ...[
          SizedBox(height: Tokens.space.xs),
          Text(
            [for (final x in p.platforms) platformLabels[x] ?? x].join(', '),
            style: TextStyle(
                color: Tokens.palette.textDim, fontSize: Tokens.type.caption),
          ),
        ],
      ],
    );
  }
}

/// The visited tree itself: who, a few numbers, what you hyped, then every
/// game grouped by branch. Read-only except for the audience verbs (react,
/// hype, follow) and Plant.
class _VisitBody extends StatelessWidget {
  const _VisitBody({
    required this.tree,
    required this.person,
    required this.isMine,
    required this.onPlant,
    required this.owned,
    required this.hyped,
    required this.onHype,
    required this.reactions,
    required this.myId,
    required this.actionsEnabled,
    required this.onReact,
    required this.onPersonChanged,
  });

  final PublishedTree tree;
  final SocialPerson? person;
  final bool isMine;
  final ValueChanged<PublishedGame> onPlant;
  final Set<int> owned;
  final Set<int> hyped;
  final ValueChanged<PublishedGame>? onHype;
  final List<TreeReaction> reactions;
  final String? myId;
  final bool actionsEnabled;
  final ValueChanged<ReactionKind> onReact;
  final ValueChanged<SocialPerson> onPersonChanged;

  @override
  Widget build(BuildContext context) {
    final byBranch = <String, List<PublishedGame>>{};
    for (final g in tree.games) {
      byBranch.putIfAbsent(g.branchName, () => []).add(g);
    }
    final playing =
        tree.games.where((g) => g.status == Progress.playing).length;
    final hypedGames = [
      for (final g in tree.games)
        if (hyped.contains(g.igdbId)) g,
    ];

    return ListView(
      padding: EdgeInsets.all(Tokens.space.md),
      children: [
        _PersonHeader(
          person: person ?? SocialPerson(profile: tree.owner),
          isMine: isMine || person == null,
          onChanged: onPersonChanged,
        ),
        SizedBox(height: Tokens.space.md),
        Row(children: [
          _Stat(n: tree.harvestedCount, word: 'Finished'),
          _Stat(n: playing, word: 'Playing'),
          _Stat(n: tree.games.length, word: 'Games'),
          _Stat(n: tree.level, word: 'Level'),
        ]),
        SizedBox(height: Tokens.space.md),
        _ReactionBar(
          reactions: reactions,
          myId: myId,
          showCounts: isMine,
          enabled: actionsEnabled,
          onReact: onReact,
        ),
        if (hypedGames.isNotEmpty) ...[
          SizedBox(height: Tokens.space.md),
          Text('You hyped',
              style: TextStyle(
                  fontSize: Tokens.type.body,
                  fontWeight: FontWeight.w600,
                  color: Tokens.palette.text)),
          SizedBox(height: Tokens.space.xs),
          SizedBox(
            height: 64,
            child: ListView(
              key: const Key('visit-hyped'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final g in hypedGames)
                  Padding(
                    padding: EdgeInsets.only(right: Tokens.space.xs),
                    child: Tooltip(
                      message: g.title,
                      child: _Cover(game: g, size: 48),
                    ),
                  ),
              ],
            ),
          ),
        ],
        SizedBox(height: Tokens.space.md),
        if (tree.games.isEmpty)
          SoftCard(
            deep: true,
            child: Text(
              'Nothing on this tree yet.',
              style: TextStyle(color: Tokens.palette.textDim, fontSize: Tokens.type.body),
            ),
          )
        else
          for (final entry in byBranch.entries) ...[
            Text(
              entry.key,
              style: TextStyle(
                fontSize: Tokens.type.body,
                fontWeight: FontWeight.w600,
                color: Tokens.palette.text,
              ),
            ),
            SizedBox(height: Tokens.space.xs),
            for (final g in entry.value)
              _VisitRow(
                game: g,
                owned: owned.contains(g.igdbId),
                hyped: hyped.contains(g.igdbId),
                onPlant: () => onPlant(g),
                onHype: onHype == null ? null : () => onHype!(g),
              ),
            SizedBox(height: Tokens.space.sm),
          ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.n, required this.word});

  final int n;
  final String word;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          container: true,
          label: '$n $word',
          excludeSemantics: true,
          child: Column(children: [
            Text('$n',
                style: TextStyle(
                    fontFamily: Tokens.type.displayFamily,
                    fontSize: Tokens.type.title,
                    fontWeight: FontWeight.w700,
                    color: Tokens.palette.text)),
            Text(word,
                style: TextStyle(
                    color: Tokens.palette.textDim,
                    fontSize: Tokens.type.caption)),
          ]),
        ),
      );
}

/// The audience verbs on the whole tree: admire, wishlist, played.
///
/// A visitor sees which ones THEY gave, highlighted, and no numbers; the
/// owner, visiting their own tree, sees the counts. Nobody else's reactions
/// are ever shown as a tally to a third person.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactions,
    required this.myId,
    required this.showCounts,
    required this.enabled,
    required this.onReact,
  });

  final List<TreeReaction> reactions;
  final String? myId;
  final bool showCounts;
  final bool enabled;
  final ValueChanged<ReactionKind> onReact;

  @override
  Widget build(BuildContext context) {
    Widget button(ReactionKind kind, IconData icon, String label) {
      final count = reactions.where((r) => r.kind == kind).length;
      final mine = myId != null &&
          reactions.any((r) => r.kind == kind && r.fromProfileId == myId);
      return Expanded(
        child: _ReactionButton(
          icon: icon,
          label: label,
          count: showCounts ? count : null,
          selected: mine,
          onTap: enabled ? () => onReact(kind) : null,
        ),
      );
    }

    return Row(
      children: [
        button(ReactionKind.admire, Icons.auto_awesome, 'Admire'),
        SizedBox(width: Tokens.space.xs),
        button(ReactionKind.wishlist, Icons.bookmark_outline, 'Wishlist'),
        SizedBox(width: Tokens.space.xs),
        button(ReactionKind.played, Icons.videogame_asset_outlined, 'Played too'),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final text = n == null ? label : '$label${n > 0 ? ' $n' : ''}';
    return Semantics(
      label: text,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: SoftCard(
        deep: selected,
        onTap: onTap,
        padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Tokens.palette.text : Tokens.palette.textDim,
            ),
            SizedBox(height: Tokens.space.xxs),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: selected ? Tokens.palette.text : Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.game, required this.size});

  final PublishedGame game;
  final double size;

  @override
  Widget build(BuildContext context) => GlowOrb(
        diameter: size,
        glow: game.status == Progress.finished ? 0.6 : 0.2,
        image: game.coverUrl == null ? null : NetworkImage(game.coverUrl!),
        child: game.coverUrl == null
            ? Text(
                game.title.isEmpty ? '?' : game.title[0].toUpperCase(),
                style: TextStyle(
                    color: Tokens.palette.text, fontWeight: FontWeight.w700),
              )
            : null,
      );
}

/// One game on a visited tree. The row a user's OWN tree would let them edit
/// or rate; here it offers hype and Plant, because visiting is read-only by
/// design.
class _VisitRow extends StatelessWidget {
  const _VisitRow({
    required this.game,
    required this.owned,
    required this.hyped,
    required this.onPlant,
    required this.onHype,
  });

  final PublishedGame game;
  final bool owned;
  final bool hyped;
  final VoidCallback onPlant;

  /// Null on your own tree: you do not hype your own games.
  final VoidCallback? onHype;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: SoftCard(
          deep: true,
          child: Row(
            children: [
              _Cover(game: game, size: 40),
              SizedBox(width: Tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      game.rating != null
                          ? '${game.status.label}, ${game.rating} of 5'
                          : game.status.label,
                      style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim),
                    ),
                  ],
                ),
              ),
              if (onHype != null)
                IconButton(
                  key: Key('hype-${game.igdbId}'),
                  tooltip: hyped ? 'Hyped. Tap to undo' : 'Hype ${game.title}',
                  isSelected: hyped,
                  onPressed: onHype,
                  icon: Icon(
                    hyped
                        ? Icons.local_fire_department
                        : Icons.local_fire_department_outlined,
                    color: hyped ? Tokens.palette.text : Tokens.palette.textDim,
                  ),
                ),
              // "Plant" not "Add": DESIGN.md's own verb. It lands in your
              // wishlist as a seed, crediting them. Already yours, it says so.
              owned
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: Tokens.space.xs),
                      child: Text('In yours',
                          key: Key('owned-${game.igdbId}'),
                          style: TextStyle(
                              color: Tokens.palette.textDim,
                              fontSize: Tokens.type.caption)),
                    )
                  : Semantics(
                      label: 'Plant ${game.title}, grafted onto your wishlist',
                      button: true,
                      excludeSemantics: true,
                      child: TextButton(
                        key: Key('plant-${game.igdbId}'),
                        onPressed: onPlant,
                        child: const Text('Plant'),
                      ),
                    ),
            ],
          ),
        ),
      );
}
