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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final backend = context.read<SocialBackend>();
    _future = backend.treeByHandle(widget.handle);
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
        content: Text('Planted ${game.title} in your soil'),
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
                return _VisitBody(tree: snapshot.data!, onPlant: _plant);
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
/// Read-only throughout -- the only interactive element on any row is Plant.
class _VisitBody extends StatelessWidget {
  const _VisitBody({required this.tree, required this.onPlant});

  final PublishedTree tree;
  final ValueChanged<PublishedGame> onPlant;

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
