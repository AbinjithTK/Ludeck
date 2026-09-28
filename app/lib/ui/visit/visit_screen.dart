// Visiting: docs/DESIGN.md section 6, "Social: visiting, not competing".
//
// "Visit a friend's tree. Read-only. See their branches, their harvests." and
// "Plant from a friend's tree. One tap moves a fruit you saw into your soil as
// a seed, crediting them. This is the loop: a visit produces a capture." This
// screen is exactly those two verbs, and nothing else -- no editing, no rating
// someone else's row, no status change. Rows offer "Plant" instead of the edit
// affordance a row on your OWN tree would have.
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

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../gamified/primitives.dart';
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

  // Reaction/follow state is read separately from the tree itself: reacting
  // does not change what the tree contains, so re-fetching the whole tree on
  // every tap would be wasted work and would also flicker every row while it
  // reloads. Loaded once alongside the tree, updated locally after a write
  // succeeds.
  List<TreeReaction> _reactions = const [];
  bool _following = false;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final backend = context.read<SocialBackend>();
    _future = backend.treeByHandle(widget.handle);
    _loadReactionsAndFollow(backend);
  }

  Future<void> _loadReactionsAndFollow(SocialBackend backend) async {
    try {
      final reactions = await backend.reactionsFor(widget.handle);
      // following() requires sign-in; a signed-out visitor simply cannot be
      // following anyone, which is a real answer, not an error.
      final follows = backend.currentProfile == null
          ? const <String>[]
          : await backend.following();
      if (!mounted) return;
      setState(() {
        _reactions = reactions;
        _following = follows.contains(widget.handle);
      });
    } on SocialException {
      // Reactions/follow state failing to load should not block the tree
      // itself from rendering -- the counts simply start at zero.
    }
  }

  bool get _signedIn => context.read<SocialBackend>().currentProfile != null;

  Future<void> _react(ReactionKind kind) async {
    final backend = context.read<SocialBackend>();
    setState(() => _actionInFlight = true);
    try {
      if (!_signedIn) await backend.signIn();
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

  Future<void> _toggleFollow() async {
    final backend = context.read<SocialBackend>();
    final next = !_following;
    setState(() {
      _following = next; // optimistic -- follow/unfollow is a toggle a user
      _actionInFlight = true; // expects to see reflected immediately.
    });
    try {
      if (!_signedIn) await backend.signIn();
      await backend.setFollowing(widget.handle, next);
      if (!mounted) return;
      setState(() => _actionInFlight = false);
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        _following = !next; // roll back the optimistic flip.
        _actionInFlight = false;
      });
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
    final store = context.read<LudeckStore>();
    await store.addShared(
      TreeItem(
        // Built straight from what the visitor actually saw on the public
        // tree -- no second catalogue round trip, and no risk of resolving to
        // a different game than the one they tapped.
        game: Game(igdbId: game.igdbId, title: game.title, coverUrl: game.coverUrl),
        entry: Entry(
          igdbId: game.igdbId,
          // A capture is a recommendation, not a purchase -- same rule
          // main.dart's share-intake path already follows.
          ownership: Ownership.spotted,
          progress: Progress.untouched,
          // "crediting them": the owner's HANDLE, their public identity, is
          // what recommendedBy is set to. This is the INTAKE side the checker
          // rule's own comment carves out -- receiving a recommendation is how
          // recommendedBy gets filled in the first place. It is never sent
          // back out with the same value; a re-share of the planted seed would
          // go through toPublished, which drops it again.
          recommendedBy: widget.handle,
        ),
        copies: const [],
      ),
      Source(
        igdbId: game.igdbId,
        // Not any specific platform -- the source is another Ludeck tree, and
        // there is no dedicated SourceKind for that. `web` is the closest
        // honest fit among the real values (docs/DECISIONS.md's vocabulary is
        // frozen; adding a case is a decision for a future stage, not this
        // one). `manual` because the visitor explicitly tapped Plant -- the
        // strongest MatchMethod, by definition, since nothing was guessed.
        kind: SourceKind.web,
        matchMethod: MatchMethod.manual,
        addedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Grafted ${game.title} onto your tree'),
        backgroundColor: Tokens.cosmos.panelDeep,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.palette.bg,
        appBar: AppBar(
          backgroundColor: Tokens.palette.bg,
          foregroundColor: Tokens.palette.text,
          title: Text(
            '@${widget.handle}\'s tree',
            style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
          ),
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
                  return _VisitError(
                    error: snapshot.error,
                    handle: widget.handle,
                  );
                }
                return _VisitBody(
                  tree: snapshot.data!,
                  onPlant: _plant,
                  reactions: _reactions,
                  isFollowing: _following,
                  actionsEnabled: !_actionInFlight,
                  onReact: _react,
                  onToggleFollow: _toggleFollow,
                );
              },
            ),
          ),
        ),
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

/// The visited tree itself: owner summary, then every game grouped by branch.
/// Read-only except for the audience verbs (react, follow) and Plant.
class _VisitBody extends StatelessWidget {
  const _VisitBody({
    required this.tree,
    required this.onPlant,
    required this.reactions,
    required this.isFollowing,
    required this.actionsEnabled,
    required this.onReact,
    required this.onToggleFollow,
  });

  final PublishedTree tree;
  final ValueChanged<PublishedGame> onPlant;
  final List<TreeReaction> reactions;
  final bool isFollowing;
  final bool actionsEnabled;
  final ValueChanged<ReactionKind> onReact;
  final VoidCallback onToggleFollow;

  int _count(ReactionKind kind) =>
      reactions.where((r) => r.kind == kind).length;

  @override
  Widget build(BuildContext context) {
    final byBranch = <String, List<PublishedGame>>{};
    for (final g in tree.games) {
      byBranch.putIfAbsent(g.branchName, () => []).add(g);
    }

    return ListView(
      padding: EdgeInsets.all(Tokens.space.md),
      children: [
        SoftCard(
          child: Row(
            children: [
              GlowOrb(diameter: 48, glow: 0.7, child: Text('${tree.level}')),
              SizedBox(width: Tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tree.owner.displayName,
                      style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.title,
                        fontWeight: FontWeight.w700,
                        color: Tokens.palette.text,
                      ),
                    ),
                    Text(
                      'Level ${tree.level}  ·  ${tree.harvestedCount} harvested',
                      style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: Tokens.space.sm),
        _ReactionBar(
          admireCount: _count(ReactionKind.admire),
          wishlistCount: _count(ReactionKind.wishlist),
          playedCount: _count(ReactionKind.played),
          isFollowing: isFollowing,
          enabled: actionsEnabled,
          onReact: onReact,
          onToggleFollow: onToggleFollow,
        ),
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
            for (final g in entry.value) _VisitRow(game: g, onPlant: () => onPlant(g)),
            SizedBox(height: Tokens.space.sm),
          ],
      ],
    );
  }
}

/// The audience verbs: three reactions (admire/wishlist/played) with their
/// live counts, plus follow. Distinct row from Plant's per-game buttons --
/// these apply to the WHOLE tree, not one game.
///
/// Each reaction is a TOGGLE per visitor (tapping a kind you already gave
/// again is a no-op on the backend's side, per FakeSocialBackend/RLS's unique
/// constraint), so this bar shows counts, not a per-visitor selected state --
/// the backend has no method to ask "did I react with X", and adding one
/// is more than this stage needs.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.admireCount,
    required this.wishlistCount,
    required this.playedCount,
    required this.isFollowing,
    required this.enabled,
    required this.onReact,
    required this.onToggleFollow,
  });

  final int admireCount;
  final int wishlistCount;
  final int playedCount;
  final bool isFollowing;
  final bool enabled;
  final ValueChanged<ReactionKind> onReact;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ReactionButton(
              icon: Icons.auto_awesome,
              label: 'Admire',
              count: admireCount,
              onTap: enabled ? () => onReact(ReactionKind.admire) : null,
            ),
          ),
          SizedBox(width: Tokens.space.xs),
          Expanded(
            child: _ReactionButton(
              icon: Icons.bookmark_outline,
              label: 'Wishlist',
              count: wishlistCount,
              onTap: enabled ? () => onReact(ReactionKind.wishlist) : null,
            ),
          ),
          SizedBox(width: Tokens.space.xs),
          Expanded(
            child: _ReactionButton(
              icon: Icons.videogame_asset_outlined,
              label: 'Played too',
              count: playedCount,
              onTap: enabled ? () => onReact(ReactionKind.played) : null,
            ),
          ),
          SizedBox(width: Tokens.space.xs),
          Expanded(
            child: _ReactionButton(
              icon: isFollowing ? Icons.notifications_active : Icons.notifications_none,
              label: isFollowing ? 'Following' : 'Follow',
              count: null,
              selected: isFollowing,
              onTap: enabled ? onToggleFollow : null,
            ),
          ),
        ],
      );
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
              color: selected ? Tokens.palette.accent : Tokens.palette.text,
            ),
            SizedBox(height: Tokens.space.xxs),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One game on a visited tree. The row a user's OWN tree would let them edit
/// or rate; here it offers exactly one action -- Plant -- because visiting is
/// read-only by design.
class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.game, required this.onPlant});

  final PublishedGame game;
  final VoidCallback onPlant;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: SoftCard(
          deep: true,
          child: Row(
            children: [
              GlowOrb(
                diameter: 40,
                glow: game.status == Progress.finished ? 0.6 : 0.2,
                image: game.coverUrl == null
                    ? null
                    : NetworkImage(game.coverUrl!),
                child: game.coverUrl == null
                    ? Text(
                        game.title.isEmpty ? '?' : game.title[0].toUpperCase(),
                        style: TextStyle(color: Tokens.palette.text, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
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
                          ? '${game.status.tree} · ${game.rating}/5'
                          : game.status.tree,
                      style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim),
                    ),
                  ],
                ),
              ),
              // The only tappable thing on this row. "Plant" not "Add" --
              // DESIGN.md's own verb, and distinct from any edit affordance a
              // row on the visitor's own tree would carry.
              TextButton(
                onPressed: onPlant,
                child: const Text('Plant'),
              ),
            ],
          ),
        ),
      );
}
