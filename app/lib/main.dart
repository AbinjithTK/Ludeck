import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/enums.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'services/catalog_service.dart';
import 'services/share_intake.dart';
import 'services/http_catalog.dart';
import 'services/link_metadata.dart';
import 'services/cover_art_cache.dart';
import 'services/share_resolver.dart';
import 'services/social/social_backend.dart';
import 'services/social/social_service.dart';
import 'state/ludeck_store.dart';
import 'ui/intake/confirm_sheet.dart';
import 'ui/add/add_screen.dart';
import 'ui/branches/branch_screen.dart';
import 'ui/chrome_metrics.dart';
import 'ui/harvest/rating_sheet.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/profile/profile_screen.dart';
import 'ui/tokens.dart';
import 'ui/shell/add_menu.dart';
import 'ui/shell/tree_header.dart';
import 'ui/gamified/primitives.dart';
import 'ui/map/branching_tree_view.dart';

Future<void> main() async {
  // Required before any plugin call, and Repository.open touches path_provider.
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repository.open();
  // No URL/key configured on this build yet -- resolves instantly to the fake
  // in local-only mode. Once a Supabase project exists (docs/DEPLOY-PROXY.md),
  // its URL and publishable key are passed here, and publishing starts leaving
  // the device instead of staying local.
  final social = await resolveSocialBackend();
  runApp(LudeckApp(repo: repo, social: social));
}

class LudeckApp extends StatelessWidget {
  const LudeckApp({super.key, required this.repo, required this.social});

  final Repository repo;
  final SocialBackend social;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.type;
    // The store is created here, above MaterialApp, so it outlives any route
    // and a sheet pushed on top of the screen reads the same state the screen
    // does. The social backend is provided the same way, for the same reason --
    // the publish screen and the share card both need it, and neither should
    // have to be handed it explicitly through a route argument.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LudeckStore>(create: (_) => LudeckStore(repo)..load()),
        Provider<SocialBackend>.value(value: social),
      ],
      child: MaterialApp(
      title: 'Ludeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Tokens.palette.bg,
        colorScheme: ColorScheme.dark(
          surface: Tokens.palette.bg,
          onSurface: Tokens.palette.text,
          primary: Tokens.palette.accent,
          onPrimary: Tokens.palette.bg,
          error: Tokens.palette.danger,
        ),
        // Tracking and leading are size-specific. One fixed value would be
        // wrong somewhere: display text reads loose as it grows, body does not.
        textTheme: TextTheme(
          displaySmall: TextStyle(
            fontSize: t.display,
            height: t.leadingDisplay,
            letterSpacing: t.trackingDisplay,
            fontWeight: FontWeight.w600,
            color: Tokens.palette.text,
          ),
          titleMedium: TextStyle(
            fontSize: t.title,
            height: t.leadingTitle,
            letterSpacing: t.trackingTitle,
            fontWeight: FontWeight.w500,
            color: Tokens.palette.text,
          ),
          bodyMedium: TextStyle(
            fontSize: t.body,
            height: t.leadingBody,
            color: Tokens.palette.text,
          ),
          labelSmall: TextStyle(
            fontSize: t.caption,
            color: Tokens.palette.textDim,
          ),
        ),
      ),
      home: _StartupGate(
        child: TreeScreen(
          metadata: LinkMetadataReader(),
          coverCache: CoverArtCache(),
        ),
      ),
      ),
    );
  }
}

/// Decides between onboarding and the real home screen at startup, based on
/// whether onboarding has been shown before. A gate rather than routing logic
/// inside TreeScreen itself, so TreeScreen's own tests (which construct it
/// directly) are untouched by this.
class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.child});

  final Widget child;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<bool> _seen;

  @override
  void initState() {
    super.initState();
    _seen = hasSeenOnboarding();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _seen,
        builder: (context, snapshot) {
          // While the flag itself is loading, show the real screen underneath
          // rather than a blank frame -- if onboarding is needed, it appears a
          // moment later; nothing is lost by not blocking on this read.
          if (snapshot.data == false) {
            return OnboardingScreen(
              // A block body, not `() => _seen = Future.value(true)` -- that
              // arrow-body's value is the assignment expression's own value,
              // which is a Future (the RHS type), so the callback's INFERRED
              // return type becomes Future<bool> instead of void. setState
              // asserts its callback returns void and throws at runtime on a
              // real device tap (confirmed via logcat, not by inspection) --
              // this compiled clean and every widget test using onDone still
              // passed, because none of them drove onDone through
              // _StartupGate's own wiring (test/startup_gate_test.dart now
              // does).
              onDone: () {
                setState(() {
                  _seen = Future.value(true);
                });
              },
            );
          }
          return widget.child;
        },
      );
}

class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    this.intake = const PlatformShareIntake(),
    this.catalog,
    this.metadata,
    this.coverCache,
  });

  /// Reads a shared link's page title, which is what turns a link into a game.
  ///
  /// Defaults to NULL, and the default is the safe one on purpose: a widget test
  /// that pumps this screen must not reach the network, and a null here disables
  /// the page-title tier outright rather than relying on a fake to stay silent.
  /// LudeckApp supplies the real reader, so production wiring is explicit at the
  /// top of the tree instead of hidden in a default argument.
  final LinkMetadataReader? metadata;

  /// Looks up cover art for a row that has none. Same null-default reasoning as
  /// [metadata]: a widget test pumping this screen must not reach the network.
  final CoverArtCache? coverCache;

  /// Where shared text arrives from. Injectable so a test can hand one in
  /// without an Android activity behind it.
  final ShareIntake intake;

  /// Game facts. Defaults to the fixture catalogue, which is what actually runs
  /// until the IGDB proxy is deployed.
  final CatalogSource? catalog;

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> with WidgetsBindingObserver {
  /// The collection, the skipped count, the loading flag and the error all belong
  /// to `LudeckStore`, which is read from the provider. A screen holding both a
  /// Repository and a store would be two sources of truth for the same rows.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // resolveCatalog(), NOT FixtureCatalog(). This line said FixtureCatalog for
    // most of the project's life, which meant the shipped app searched ten
    // hardcoded rows and could not find Grand Theft Auto V -- while a test
    // asserting resolveCatalog() returned the right thing passed happily,
    // because nothing in the app ever called it. A factory the app does not use
    // is not a seam, it is dead code with a test attached.
    _catalog = widget.catalog ?? resolveCatalog();
    // The metadata reader is what turns a shared link into a game. It needs no
    // credentials and no deployed proxy -- only looking a game up does -- so it is
    // supplied here rather than waiting on anything. Tests construct the resolver
    // without it, which keeps them off the network.
    _resolver = ShareResolver(catalog: _catalog, metadata: widget.metadata);
    // The store is loaded where it is created, so there is nothing to load
    // here. A share that arrived with a cold start is drained after the first
    // frame, once the provider is reachable from this context.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainShare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A share into an already-running app arrives at MainActivity.onNewIntent
  /// and then the activity resumes, so resume is where it gets picked up. The
  /// intake clears itself when taken, so asking on every resume is safe.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drainShare();
  }

  late CatalogSource _catalog;
  late ShareResolver _resolver;

  /// Guards against two overlapping sheets. A resume can land while one is
  /// already open, and two stacked sheets for one share is not a state anybody
  /// can reason about.
  bool _handlingShare = false;

  Future<void> _drainShare() async {
    if (_handlingShare) return;
    _handlingShare = true;
    try {
      final text = await widget.intake.takePending();
      if (text == null || !mounted) return;

      final resolution = await _resolver.resolve(text);
      if (!mounted) return;

      final choice = await showIntakeSheet(context, resolution);
      if (choice == null || choice.accepted.isEmpty) return;

      await _applyIntake(resolution, choice);
    } finally {
      _handlingShare = false;
    }
  }

  /// Writes the accepted games and records where each came from.
  ///
  /// `upsert` does nothing on an existing entry, which is deliberate: sharing a
  /// game you already own must not reset its progress or its rating. The source
  /// row is still added, because the fact that it came up again is itself worth
  /// keeping.
  Future<void> _applyIntake(ShareResolution r, IntakeChoice choice) async {
    final now = DateTime.now();
    final store = context.read<LudeckStore>();

    for (final candidate in choice.accepted) {
      final id = candidate.igdbId;
      if (id == null) continue;

      final game = await _catalog.byId(id);
      if (game == null) continue;

      // One write, one reload. Two separate calls left the collection briefly
      // holding a game with no source, and cost two full reload cycles per game.
      await store.addShared(
        TreeItem(
          game: game,
          entry: Entry(
            igdbId: id,
            // A share is a recommendation, not a purchase. Ownership and
            // progress are separate axes and neither is implied by the other.
            ownership: Ownership.spotted,
            progress: Progress.untouched,
            recommendedBy: choice.recommendedBy,
          ),
          copies: const [],
        ),
        Source(
          igdbId: id,
          url: candidate.link?.uri.toString(),
          kind: r.kind,
          matchMethod: candidate.method,
          addedAt: now,
        ),
      );
    }

    if (!mounted) return;

    final n = choice.accepted.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Tokens.palette.surface,
        content: Text(
          n == 1
              ? 'Added ${choice.accepted.single.title}.'
              : 'Added $n games.',
          style: TextStyle(color: Tokens.palette.text),
        ),
      ),
    );
  }

  /// Moves a dragged game from one branch to another, or off every branch.
  ///
  /// A MOVE, not a copy: the old placement is removed as well as the new one
  /// added. Without the removal a single drag would leave the game hanging on
  /// two branches, which is legal in this model (a game genuinely can sit on
  /// several) and therefore would not look like a bug -- it would look like the
  /// app had silently duplicated the game.
  ///
  /// `toBranchId` null means it was dropped in the soil: taken off its branch,
  /// not deleted. Nothing the user recorded is destroyed by filing.
  Future<void> _moveGame(
    LudeckStore store,
    GameDrag drag,
    int? toBranchId,
  ) async {
    final id = drag.item.game.igdbId;
    final from = drag.fromBranchId;
    if (from == toBranchId) return;

    if (toBranchId != null) {
      await store.place(id, toBranchId);
    }
    if (from != null) {
      await store.unplace(id, from);
    }

    if (!mounted) return;

    // Named feedback, because the tree hides branch names: after a drop the user
    // has no on-screen way to confirm WHICH branch received the game, and a
    // silent success would make the one destructive-looking gesture in the app
    // unverifiable.
    final branchName = toBranchId == null
        ? null
        : store.branches
            .where((b) => b.id == toBranchId)
            .map((b) => b.name)
            .firstOrNull;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Tokens.palette.surface,
        duration: const Duration(seconds: 2),
        content: Text(
          branchName == null
              ? '${drag.item.game.title} is back in the soil.'
              : '${drag.item.game.title} moved to $branchName.',
          style: TextStyle(color: Tokens.palette.text),
        ),
      ),
    );
  }

  /// Routes an add action.
  ///
  /// Search and manual both land on the same screen: the difference between them
  /// was never a different flow, only a different expectation of what the
  /// catalogue would return, and the screen says which source it is searching.
  /// Pasting a link is still the share path and has no screen of its own, because
  /// the share sheet already handles it better than a paste box would.
  void _onAdd(AddAction action) {
    switch (action) {
      case AddAction.search:
      case AddAction.manual:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AddScreen(catalog: _catalog),
        ));
      case AddAction.pasteLink:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Tokens.palette.surface,
            duration: const Duration(seconds: 4),
            content: Text(
              // Points at the thing that already works rather than opening a box
              // that would do the same job worse.
              'Share a link to Ludeck from any app and it lands here, with the '
              'link kept.',
              style: TextStyle(color: Tokens.palette.text),
            ),
          ),
        );
    }
  }

  /// Writes the progress, then asks for a rating IF this was a harvest.
  ///
  /// The trigger is the TRANSITION into finished, not the finished state. Three
  /// consequences, each deliberate:
  ///
  /// - Re-selecting "finished" on an already-finished game asks nothing. The
  ///   harvest already happened.
  /// - A game that is already rated is not asked again. Skipping is a real
  ///   answer and re-asking would make it a deferral.
  /// - Nothing anywhere else opens this on its own. A rating belongs to the
  ///   harvest, and a star control living permanently on a row would turn the
  ///   collection into a scoring chore.
  Future<void> _setProgressAndMaybeRate(
    LudeckStore store,
    TreeItem item,
    Progress next,
  ) async {
    final wasFinished = item.entry.progress == Progress.finished;
    await store.setProgress(item.game.igdbId, next);

    final isHarvest = next == Progress.finished && !wasFinished;
    if (!isHarvest || item.entry.rating != null) return;
    // A failed write must not be followed by a question about it.
    if (store.error != null || !mounted) return;

    await _askForRating(store, item);
  }

  /// Opens the rating sheet and writes whatever comes back.
  ///
  /// A null result is a skip and writes nothing at all, which is different from
  /// a choice carrying a null rating: that one clears an existing rating.
  Future<void> _askForRating(LudeckStore store, TreeItem item) async {
    final choice = await showRatingSheet(
      context,
      title: item.game.title,
      initial: item.entry.rating,
    );
    if (choice == null || !mounted) return;
    await store.setRating(item.game.igdbId, choice.rating);
  }

  /// Opens the branches screen.
  ///
  /// A pushed route rather than a sheet: create, rename, reorder and delete is
  /// more than one decision, and a sheet that tall is just a screen with a worse
  /// back gesture. The store is provided above `MaterialApp`, so the pushed route
  /// reads the same state this screen does with no argument passing.
  void _openBranches() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BranchScreen()),
    );
  }

  /// Opens the profile. Same no-argument pattern as `_openBranches`: the screen
  /// reads the store, so nothing has to be threaded through the route.
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  /// Explains a nonzero skipped count when the user taps the notice.
  ///
  /// States what happened, that nothing else was touched, and gives one
  /// concrete thing to do. What it does not do is apologise or speculate about
  /// cause: this is a rare failure mode with one honest description, and
  /// dressing it up as either a disaster or a shrug would both be lies.
  void _showSkippedNotice() {
    final n = context.read<LudeckStore>().skipped;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.palette.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Tokens.space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n == 1
                    ? 'One game could not be read'
                    : '$n games could not be read',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: Tokens.space.sm),
              Text(
                'Its saved status did not match anything this version of the '
                'app understands. This can happen after an update changes what '
                'a status can be.',
                style: TextStyle(
                    fontSize: Tokens.type.body, color: Tokens.palette.text),
              ),
              SizedBox(height: Tokens.space.sm),
              Text(
                'Nothing was deleted. Every other game on the tree is exactly '
                'as you left it.',
                style: TextStyle(
                    fontSize: Tokens.type.body, color: Tokens.palette.text),
              ),
              SizedBox(height: Tokens.space.sm),
              Text(
                'Updating to the latest version usually fixes this. If it '
                'keeps happening after that, it is worth reporting.',
                style: TextStyle(
                    fontSize: Tokens.type.body, color: Tokens.palette.textDim),
              ),
              SizedBox(height: Tokens.space.md),
            ],
          ),
        ),
      ),
    );
  }

  /// Two independent axes in one sheet, visibly separate.
  ///
  /// They are separate sections rather than one list because a single list of
  /// options is how a user learns, wrongly, that these are steps in a chain.
  /// Selling a game keeps its completion record, and the sheet has to show that
  /// is possible.
  void _openStatusSheet(TreeItem item) {
    // Captured before the sheet is pushed. The sheet's own builder context is a
    // different subtree, and reading the provider from it after the screen has
    // rebuilt is how a "deactivated widget's ancestor" error appears.
    final store = context.read<LudeckStore>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.palette.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(Tokens.space.md, Tokens.space.md,
                    Tokens.space.md, Tokens.space.xs),
                child: Text(item.game.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              _sheetHeading('How far did you get'),
              for (final p in Progress.values)
                _sheetOption(
                  tree: p.tree,
                  label: p.label,
                  selected: p == item.entry.progress,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setProgressAndMaybeRate(store, item, p);
                  },
                ),
              Divider(color: Tokens.palette.bg, height: Tokens.space.md),
              _sheetHeading('Do you have it'),
              for (final o in Ownership.values)
                _sheetOption(
                  tree: o.tree,
                  label: o.label,
                  selected: o == item.entry.ownership,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    store.setOwnership(item.game.igdbId, o);
                  },
                ),

              // Only for a game that has actually been harvested, and only as
              // something the user reaches for.
              //
              // The rating sheet asks once, on the harvest, and skipping it is a
              // real answer. Without this row a skip would make the rating
              // permanently unreachable, which is a functional hole rather than
              // restraint. It is not a nag: no badge, no count, nothing appears
              // unless the user opens this sheet themselves.
              if (item.isHarvested) ...[
                Divider(color: Tokens.palette.bg, height: Tokens.space.md),
                _sheetHeading('What did you think'),
                ListTile(
                  dense: true,
                  leading: Icon(
                    item.entry.rating == null
                        ? Icons.star_border
                        : Icons.star,
                    size: 14,
                    color: item.entry.rating == null
                        ? Tokens.palette.textDim
                        : Tokens.palette.accent,
                  ),
                  title: Text(
                    item.entry.rating == null
                        ? 'Rate it'
                        : 'Rated ${item.entry.rating} out of 5',
                    style: TextStyle(
                      fontSize: Tokens.type.body,
                      color: Tokens.palette.text,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _askForRating(store, item);
                  },
                ),
              ],
              SizedBox(height: Tokens.space.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeading(String text) => Padding(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.md, Tokens.space.xs, Tokens.space.md, Tokens.space.xxs),
        child: Text(text,
            style: TextStyle(
                fontSize: Tokens.type.caption, color: Tokens.palette.textDim)),
      );

  Widget _sheetOption({
    required String tree,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(
          selected ? Icons.circle : Icons.circle_outlined,
          size: 14,
          color: selected ? Tokens.palette.accent : Tokens.palette.textDim,
        ),
        title: Text(
          tree,
          style: TextStyle(
            fontSize: Tokens.type.body,
            color: selected ? Tokens.palette.text : Tokens.palette.textDim,
          ),
        ),
        subtitle: Text(label,
            style: TextStyle(
                fontSize: Tokens.type.caption, color: Tokens.palette.textDim)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore>();
    final items = store.items;

    // The first read. Deliberately quiet: no spinner, because the read is fast
    // and a spinner that flashes is worse than a moment of nothing. Null is not
    // the same as an empty collection: empty renders the real "nothing planted
    // yet" headline, this renders nothing at all.
    if (items == null) {
      // Unless the very first read FAILED, in which case a blank screen would
      // be indistinguishable from an empty collection and the user would have
      // no idea anything went wrong.
      if (store.error != null) {
        return Scaffold(body: _LoadFailure(error: store.error!, store: store));
      }
      return const Scaffold(body: SizedBox.shrink());
    }

    // Only the bottom band needs a number now. The header's height is settled
    // by layout rather than arithmetic; see ChromeMetrics for why the previous
    // computed top inset was wrong on a device.
    final chrome = ChromeMetrics.of(context);

    return Scaffold(
      // The header is a real layout sibling ABOVE the content, not an overlay
      // floating over it.
      //
      // It used to float, because the Rive tree wants to fill the whole screen
      // behind the chrome. With the plain-Flutter collection standing in for the
      // tree, floating text over a scrolling list is simply wrong: rows slid
      // under the headline and the status-bar clock, and the inset that was
      // supposed to prevent it assumed a single-line header. A header that can
      // wrap cannot be cleared by any fixed number, so the fix is structural.
      // When the tree returns it goes back into a Stack beneath this column.
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: Column(
        // Stretch, not the default centre. A Column centres its children on the
        // cross axis, which shrink-wraps the header to its text width and centres
        // the block -- the header is specified top-LEFT.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreeHeader(
            total: items.length,
            harvested: items.where((i) => i.isHarvested).length,
            seeds: items.where((i) => i.isSeed).length,
            branches: store.branches.length,
            skipped: store.skipped,
            onSkippedTap: _showSkippedNotice,
            onBranchesTap: _openBranches,
            onProfileTap: _openProfile,
          ),

          // The content layer, with the add control floating over it. Only this
          // part is a Stack, so nothing can overlap the header.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BranchingTreeView(
                  items: items,
                  branches: store.branches,
                  placements: store.placements,
                  coverCache: widget.coverCache,
                  onCoverFound: store.applyCoverUrl,
                  onMove: (drag, toBranchId) =>
                      _moveGame(store, drag, toBranchId),
                  // The header already supplies the gap above; the list only
                  // needs to clear the control at the bottom.
                  topInset: 0,
                  bottomInset: chrome.bottom,
                  // Tap opens the status sheet, because long-press is the DRAG
                  // now (press and hold moves a game between branches). The tap
                  // used to show an information snackbar, which was strictly less
                  // useful than the thing the user actually wants from a game.
                  onSelect: _openStatusSheet,
                  onHold: _openStatusSheet,
                ),

                // A fade under the add control. Padding alone only fixes where
                // the list comes to REST; while it is being dragged, rows travel
                // behind the button, and a row half-visible under a solid circle
                // reads as a rendering fault. IgnorePointer is load bearing: a
                // scrim that took pointer events would make the bottom band of
                // the screen dead to touch.
                _Scrim(extent: chrome.bottom),

                // Bottom left, per the reference. The add action is the one
                // thing a new person has to find, so it sits where a thumb
                // already rests.
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: Tokens.space.md,
                        bottom: Tokens.space.md,
                      ),
                      child: AddMenu(onAction: _onAdd),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Shown only when the FIRST read failed, so there is no collection to render.
///
/// A blank screen would be indistinguishable from an empty collection, and
/// "your library is empty" is a much worse lie than "this did not load". Later
/// failures do not come here: the collection is already on screen and replacing
/// it with an error page would throw away readable data over one failed write.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.error, required this.store});

  final Object error;
  final LudeckStore store;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Tokens.space.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your collection did not load.',
                style: Theme.of(context).textTheme.displaySmall),
            SizedBox(height: Tokens.space.sm),
            Text(
              'Nothing was changed or deleted. This is a read that failed, so '
              'trying again is safe.',
              style: TextStyle(
                  fontSize: Tokens.type.body, color: Tokens.palette.text),
            ),
            SizedBox(height: Tokens.space.md),
            // The raw error, dim and secondary. Hiding it helps nobody: this is
            // the one screen where a user reporting a problem needs something
            // concrete to quote.
            Text('$error',
                style: TextStyle(
                    fontSize: Tokens.type.caption,
                    color: Tokens.palette.textDim)),
            SizedBox(height: Tokens.space.lg),
            TextButton(
              onPressed: store.isLoading ? null : store.load,
              child: Text(store.isLoading ? 'Trying...' : 'Try again',
                  style: TextStyle(color: Tokens.palette.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top of the screen: headline, subline, and the unreadable-rows notice.
///
/// An ordinary layout child with its own natural height, which is the whole
/// point. It previously floated over the content inside a Stack, and the content
/// padded itself by a guessed header height; that guess assumed one line of
/// display type and was short by the subline on a real device. Text wraps at
/// large text scales and on narrow screens, so no constant could have been
/// right. Laid out in sequence, an overlap is not expressible.
/// the reserved band cannot fall out of step.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.extent});

  final double extent;

  @override
  Widget build(BuildContext context) {
    final bg = Tokens.palette.bg;
    return Positioned(
      key: const Key('scrim-bottom'),
      left: 0,
      right: 0,
      bottom: 0,
      height: extent,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              // Solid for most of the band, then a short fade. Fading across the
              // whole height would leave the control sitting over a half-visible
              // row, which is the artefact this exists to remove.
              colors: [bg, bg, bg.withValues(alpha: 0)],
              stops: const [0, 0.65, 1],
            ),
          ),
        ),
      ),
    );
  }
}
