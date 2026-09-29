import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/enums.dart';
import 'data/models.dart';
import 'ui/common/name_dialog.dart';
import 'ui/publish/share_sheet.dart';
import 'data/repository.dart';
import 'services/catalog_service.dart';
import 'services/share_intake.dart';
import 'services/http_catalog.dart';
import 'services/link_metadata.dart';
import 'services/cover_art_cache.dart';
import 'services/share_resolver.dart';
import 'services/social/social_backend.dart';
import 'services/social/social_service.dart';
import 'services/social/visit_links.dart';
import 'ui/visit/visit_screen.dart';
import 'services/entitlement_service.dart';
import 'services/revenuecat_entitlement_source.dart';
import 'state/ludeck_store.dart';
import 'ui/intake/confirm_sheet.dart';
import 'ui/add/add_screen.dart';
import 'ui/friends/friends_screen.dart';
import 'ui/harvest/rating_sheet.dart';
import 'ui/library/library_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/profile/profile_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/tokens.dart';
import 'ui/shell/add_menu.dart';
// The orchard replaced the node tree / roadmap / canopy as home. Those views
// stay on disk (and in git) unimported, so reverting is one import away.
import 'ui/orchard/orchard_view.dart';
import 'ui/orchard/tree_style.dart';
import 'ui/orchard/game_sheet.dart';
import 'ui/found/found_moment.dart';
import 'domain/branch_tree.dart';

Future<void> main() async {
  // Required before any plugin call, and Repository.open touches path_provider.
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repository.open();
  // The Supabase URL and publishable key are supplied at build time with
  //   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
  // (see docs/DEPLOY-PROXY.md). With neither defined -- the default on a plain
  // build -- both read as empty and resolveSocialBackend falls back to the fake
  // in local-only mode, so publishing stays on the device. This is the supply
  // mechanism the resolver always accepted but nothing fed until now.
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final social = await resolveSocialBackend(
    supabaseUrl: supabaseUrl.isEmpty ? null : supabaseUrl,
    supabasePublishableKey: supabaseKey.isEmpty ? null : supabaseKey,
  );
  // RevenueCat's public Google SDK key, supplied the same way:
  //   --dart-define=REVENUECAT_GOOGLE_KEY=goog_...
  // Without it nothing can be bought and nobody is Pro (never the test fake,
  // which would grant Pro for free).
  const revenueCatKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
  final entitlements = await resolveEntitlementService(revenueCatKey);
  runApp(LudeckApp(repo: repo, social: social, entitlements: entitlements));
}

/// One link stream for the app's lifetime, shared. The startup gate can mount
/// the home screen more than once (onboarding, then home), and each mount
/// subscribes; a single-subscription stream throws on the second. Top-level
/// finals are lazy, so nothing touches the platform until the first listen.
final Stream<String> _appVisits = appVisitLinks().asBroadcastStream();

class LudeckApp extends StatelessWidget {
  const LudeckApp(
      {super.key, required this.repo, required this.social, this.entitlements});

  final Repository repo;
  final SocialBackend social;

  /// Who is Pro. Tests that do not pass one get a store-less service.
  final EntitlementService? entitlements;

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
        if (entitlements != null)
          Provider<EntitlementService>.value(value: entitlements!)
        else
          Provider<EntitlementService>(
            create: (_) => EntitlementService(UnavailableEntitlementSource()),
            dispose: (_, s) => s.dispose(),
          ),
      ],
      child: MaterialApp(
      title: 'Ludeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Every Text without its own family inherits this one; headlines opt
        // into Tokens.type.displayFamily explicitly.
        fontFamily: t.ui,
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
            fontFamily: t.displayFamily,
            fontSize: t.display,
            height: t.leadingDisplay,
            letterSpacing: t.trackingDisplay,
            fontWeight: FontWeight.w700,
            color: Tokens.palette.text,
          ),
          titleMedium: TextStyle(
            fontFamily: t.displayFamily,
            fontSize: t.title,
            height: t.leadingTitle,
            letterSpacing: t.trackingTitle,
            fontWeight: FontWeight.w600,
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
        // One surface for everything that rises over the orchard. The game
        // sheet and the share sheet were already night-purple glass with a
        // continuous corner; the tree menu, the shelf, the customise and
        // rating sheets, dialogs and snackbars were a flat grey from another
        // app (2026-09-28, "overall theme should be more polished"). They all
        // take the night surface from here now, not a colour of their own.
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Tokens.cosmos.hillTop,
          modalBackgroundColor: Tokens.cosmos.hillTop,
          surfaceTintColor: Tokens.cosmos.hillTop.withValues(alpha: 0),
          shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(Tokens.radius.sheet))),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Tokens.cosmos.hillTop,
          surfaceTintColor: Tokens.cosmos.hillTop.withValues(alpha: 0),
          shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(Tokens.radius.sheet)),
          titleTextStyle: TextStyle(
            fontFamily: t.displayFamily,
            fontSize: t.title,
            fontWeight: FontWeight.w700,
            color: Tokens.palette.text,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Tokens.cosmos.hillTop,
          behavior: SnackBarBehavior.floating,
          shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(Tokens.radius.panel)),
          contentTextStyle: TextStyle(
              fontFamily: t.ui, fontSize: t.body, color: Tokens.palette.text),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: Tokens.palette.text,
          textColor: Tokens.palette.text,
          titleTextStyle: TextStyle(
              fontFamily: t.ui,
              fontSize: t.body,
              fontWeight: FontWeight.w500,
              color: Tokens.palette.text),
        ),
      ),
      home: _StartupGate(
        child: TreeScreen(
          metadata: LinkMetadataReader(),
          coverCache: CoverArtCache(),
          visitLinks: _appVisits,
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
    this.visitLinks,
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

  /// Handles of shared orchards the user tapped a link to (tree_links.dart).
  /// Null in tests, so no platform channel is touched; LudeckApp supplies
  /// [appVisitLinks].
  final Stream<String>? visitLinks;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainShare();
      _backfillCoversWhenLoaded();
    });
    _visits = widget.visitLinks?.listen(_openVisit);
  }

  StreamSubscription<String>? _visits;

  /// A tapped orchard link: open that orchard, on top of whatever is showing.
  void _openVisit(String handle) {
    if (!mounted) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VisitScreen(handle: handle)));
  }

  /// With the IGDB proxy configured, games that were added without art (from
  /// the bundled catalogue, which carries none, or by hand) get their covers
  /// once, in the background, by exact title (LudeckStore.backfillCovers).
  /// Off on a plain build and in tests, which pass their own catalogue.
  void _backfillCoversWhenLoaded() {
    if (widget.catalog != null || catalogBaseUrl.isEmpty || !mounted) return;
    final store = context.read<LudeckStore>();
    var started = false;
    void go() {
      if (started || store.items == null) return;
      started = true;
      store.removeListener(go);
      unawaited(store.backfillCovers(_catalog));
    }

    store.addListener(go);
    go();
  }

  @override
  void dispose() {
    _visits?.cancel();
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
    // Games that are new to the collection get their moment afterwards; one
    // that was already there keeps its tree and gets no ceremony.
    final found = <Game>[];

    for (final candidate in choice.accepted) {
      final id = candidate.igdbId;
      if (id == null) continue;

      final game = await _catalog.byId(id);
      if (game == null) continue;
      final isNew = !(store.items ?? const []).any((i) => i.game.igdbId == id);
      if (isNew) found.add(game);

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

    // One moment per new game, in the order they were shared.
    String? tree;
    for (final game in found) {
      if (!mounted) return;
      tree = await offerTree(context, store, game);
    }
    if (!mounted) return;

    final n = choice.accepted.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 1
              ? tree != null
                  ? 'Added ${choice.accepted.single.title} to $tree.'
                  : 'Added ${choice.accepted.single.title}.'
              : 'Added $n games.',
          style: TextStyle(color: Tokens.palette.text),
        ),
      ),
    );
  }

  /// Which branch [item] currently hangs on, or null for the trunk.
  ///
  /// The model genuinely allows a game on several branches at once, so this
  /// returns the FIRST in the user's own order. The status sheet is a
  /// single-choice control, and showing two branches as simultaneously selected
  /// there would misrepresent what tapping one does.
  int? _branchIdFor(LudeckStore store, TreeItem item) {
    final id = item.game.igdbId;
    for (final b in store.branches) {
      if ((store.placements[b.id] ?? const <int>[]).contains(id)) return b.id;
    }
    return null;
  }

  /// Files a game onto [toBranchId], or takes it off every branch when null.
  ///
  /// A MOVE, not a copy: every existing placement is removed as well as the new
  /// one added. Without the removal, filing twice would leave the game hanging on
  /// two branches -- which is legal in this model and therefore would not look
  /// like a bug, it would look like the app had silently duplicated the game.
  ///
  /// Null means back on the trunk: taken off its branch, not deleted. Nothing the
  /// user recorded is destroyed by filing.
  Future<void> _fileGame(
    LudeckStore store,
    TreeItem item,
    int? toBranchId, {
    bool quiet = false,
  }) async {
    final id = item.game.igdbId;
    final from = <int>[
      for (final b in store.branches)
        if ((store.placements[b.id] ?? const <int>[]).contains(id)) b.id,
    ];
    if (from.length == 1 && from.first == toBranchId) return;
    if (from.isEmpty && toBranchId == null) return;

    if (toBranchId != null) {
      await store.place(id, toBranchId);
    }
    for (final b in from) {
      if (b != toBranchId) await store.unplace(id, b);
    }

    if (!mounted || quiet) return;

    // Named feedback, because the tree does not paint branch names: without it
    // the user has no on-screen way to confirm WHICH branch received the game.
    final branchName = toBranchId == null
        ? null
        : store.branches
            .where((b) => b.id == toBranchId)
            .map((b) => b.name)
            .firstOrNull;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          branchName == null
              ? '${item.game.title} is back on the ground.'
              : '${item.game.title} moved to $branchName.',
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

  /// Names and grows a branch from the canopy, under [parentId] or the trunk.
  ///
  /// A plain dialog for now; Stage 5 replaces it with naming in place on the
  /// sprouting twig, plus starter templates.
  Future<void> _growBranch(LudeckStore store, int? parentId) async {
    final parent = parentId == null
        ? null
        : store.branches.where((b) => b.id == parentId).firstOrNull;
    final name = await showNameDialog(
      context,
      title: parent == null
          ? 'Name this branch'
          : 'Name a branch inside ${parent.name}',
      confirmLabel: 'Grow it',
      hint: 'e.g. Couch co-op',
    );
    if (name == null) return;
    await store.createBranch(name, parentId: parentId);
  }

  /// The branch node's context menu (long-press or the â‹¯): rename, add a game
  /// here, add a sub-branch, delete. Replaces the old jump to the Branches
  /// screen -- every branch action now lives on the node itself.
  /// A tree's (or branch's) own menu: everything about THIS tree in one
  /// place, opened by tapping its name. [customise] is the tree's look
  /// (colours, wood, props), passed in by the orchard, which owns that sheet.
  void _branchMenu(LudeckStore store, Branch branch, {VoidCallback? customise}) {
    final shareable = branch.parentId == null &&
        store.tree.gamesUnder(branch.id).isNotEmpty;
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Tokens.space.md, Tokens.space.md,
                Tokens.space.md, Tokens.space.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(branch.name,
                  style: TextStyle(
                      color: Tokens.palette.text,
                      fontFamily: Tokens.type.displayFamily,
                      fontSize: Tokens.type.title,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          if (customise != null)
            ListTile(
              key: const Key('tree-menu-customise'),
              leading: Icon(Icons.palette_outlined, color: Tokens.palette.text),
              title: Text('Colours and wood',
                  style: TextStyle(color: Tokens.palette.text)),
              onTap: () {
                Navigator.of(sheet).pop();
                customise();
              },
            ),
          if (shareable)
            ListTile(
              key: const Key('tree-menu-share'),
              leading: Icon(Icons.ios_share_rounded, color: Tokens.palette.text),
              title: Text('Share this tree',
                  style: TextStyle(color: Tokens.palette.text)),
              onTap: () {
                Navigator.of(sheet).pop();
                showShareSheet(context, scope: branch.name);
              },
            ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: Tokens.palette.text),
            title: Text('Rename', style: TextStyle(color: Tokens.palette.text)),
            onTap: () {
              Navigator.of(sheet).pop();
              _renameBranch(store, branch);
            },
          ),
          ListTile(
            leading: Icon(Icons.add_photo_alternate_outlined,
                color: Tokens.palette.text),
            title: Text('Add a game here',
                style: TextStyle(color: Tokens.palette.text)),
            onTap: () {
              Navigator.of(sheet).pop();
              _addGameToBranch(branch);
            },
          ),
          ListTile(
            leading:
                Icon(Icons.account_tree_outlined, color: Tokens.palette.text),
            title: Text('Add a branch inside',
                style: TextStyle(color: Tokens.palette.text)),
            onTap: () {
              Navigator.of(sheet).pop();
              _growBranch(store, branch.id);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Tokens.palette.danger),
            title: Text(branch.parentId == null ? 'Delete tree' : 'Delete branch',
                style: TextStyle(color: Tokens.palette.danger)),
            subtitle: Text('Its games go back on the ground',
                style: TextStyle(
                    color: Tokens.palette.textDim,
                    fontSize: Tokens.type.caption)),
            onTap: () {
              Navigator.of(sheet).pop();
              _deleteBranch(store, branch);
            },
          ),
        ]),
      ),
    );
  }

  /// Rename in place. A plain dialog, prefilled with the current name.
  Future<void> _renameBranch(LudeckStore store, Branch branch) async {
    final name = await showNameDialog(
      context,
      title: branch.parentId == null ? 'Rename tree' : 'Rename branch',
      confirmLabel: 'Rename',
      initial: branch.name,
    );
    if (name == null || name == branch.name) return;
    await store.renameBranch(branch.id, name);
  }

  /// Delete a branch, with an undo that re-creates it and re-files the games
  /// that were on it. The games are never destroyed -- delete only unfiles them
  /// to the trunk -- so undo is a re-create + re-place, not a resurrection.
  Future<void> _deleteBranch(LudeckStore store, Branch branch) async {
    final placedGames = List<int>.from(store.placements[branch.id] ?? const []);
    final subCount = store.branches.where((b) => b.parentId == branch.id).length;
    await store.deleteBranch(branch.id);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          subCount > 0
              ? '"${branch.name}" deleted. Its sub-branches and games moved up.'
              : '"${branch.name}" deleted. Its games are back on the ground.',
          style: TextStyle(color: Tokens.palette.text),
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Tokens.palette.accent,
          onPressed: () async {
            await store.createBranch(branch.name, parentId: branch.parentId);
            // The re-created branch takes a new id; re-file its former games.
            final revived = store.branches
                .where((b) =>
                    b.name == branch.name && b.parentId == branch.parentId)
                .toList();
            if (revived.isNotEmpty) {
              final id = revived.last.id;
              for (final g in placedGames) {
                await store.place(g, id);
              }
            }
          },
        ),
      ),
    );
  }

  /// "Add a game here": opens the add flow scoped to file onto [branch], so a
  /// game the user adds lands on that branch rather than the trunk. AddScreen
  /// shows its own per-game feedback and does the filing.
  Future<void> _addGameToBranch(Branch branch) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddScreen(catalog: _catalog, fileOnto: branch.id),
      ),
    );
  }

  /// A fruit dragged from one tree onto another tree's dot: a MOVE. The drag
  /// already said where it goes, so no move-vs-also-add question interrupts
  /// it. The game may hang on a sub-branch of its tree, so the branch it
  /// actually leaves is looked up under [fromTree]. Ends with an undo.
  Future<void> _moveBetweenTrees(
      LudeckStore store, TreeItem item, int fromTree, int toTree) async {
    final id = item.game.igdbId;
    final shape = BranchTree(store.branches, store.placements);
    final under = {fromTree, ...shape.descendantsOf(fromTree).map((b) => b.id)};
    final from = under.firstWhere(
        (b) => (store.placements[b] ?? const <int>[]).contains(id),
        orElse: () => fromTree);
    await store.moveGame(id, fromBranchId: from, toBranchId: toTree);
    if (!mounted) return;
    final name = shape[toTree]?.name ?? 'that tree';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('${item.game.title} moved to $name.',
            style: TextStyle(color: Tokens.palette.text)),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Tokens.palette.accent,
          onPressed: () =>
              store.moveGame(id, fromBranchId: toTree, toBranchId: from),
        ),
      ),
    );
  }

  /// Opens the profile. Same no-argument pattern as `_openBranches`: the screen
  /// reads the store, so nothing has to be threaded through the route.
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
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
    // Each branch in the tree's own blossom colour: a sub-branch takes its
    // root tree's, so the choices match the trees on the meadow.
    final roots = treesOf(store.branches);
    final styles = resolveTreeStyles(
        roots.map((b) => b.id).toList(), store.treeStyles);
    final byId = {for (final b in store.branches) b.id: b};
    Color swatchOf(Branch b) {
      var r = b;
      for (var i = 0; i < 16 && r.parentId != null && byId[r.parentId] != null; i++) {
        r = byId[r.parentId]!;
      }
      final idx = roots.indexWhere((x) => x.id == r.id);
      return (styles[r.id] ?? TreeStyle.defaultFor(idx < 0 ? 0 : idx))
          .blossom
          .swatch;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.palette.bg.withValues(alpha: 0),
      builder: (sheetContext) {
        // Choices apply IN PLACE and the sheet stays open: it used to pop on
        // every tap, so answering one question closed the other two
        // (2026-09-28, "choosing one makes the window close"). Only a step
        // that opens the rating sheet closes this one first, because the two
        // sheets cannot stack.
        void closeThen(VoidCallback act) {
          Navigator.of(sheetContext).pop();
          act();
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88),
          // Re-read on every store change so the sheet shows the answer just
          // chosen; [item] is the snapshot from when it opened. Listens to
          // the store instance itself, not a Provider lookup: the sheet's
          // route lives in the Navigator, which need not be under the
          // provider (the widget tests mount it below MaterialApp).
          child: ListenableBuilder(listenable: store, builder: (_, _) {
            final live = store.items
                    ?.where((i) => i.game.igdbId == item.game.igdbId)
                    .firstOrNull ??
                item;
            return GameSheet(
              item: live,
              trees: [
                for (final b in store.branches)
                  (id: b.id, name: b.name, swatch: swatchOf(b)),
              ],
              currentTree: _branchIdFor(store, live),
              onProgress: (p) {
                final harvest = p == Progress.finished &&
                    live.entry.progress != Progress.finished &&
                    live.entry.rating == null;
                if (harvest) {
                  closeThen(() => _setProgressAndMaybeRate(store, live, p));
                } else {
                  _setProgressAndMaybeRate(store, live, p);
                }
              },
              onOwnership: (o) => store.setOwnership(live.game.igdbId, o),
              // Quiet: the sheet itself now shows where the game hangs, and a
              // snack bar would open behind it.
              onTree: (id) => _fileGame(store, live, id, quiet: true),
              onRate: () => closeThen(() => _askForRating(store, live)),
              onRemove: () =>
                  closeThen(() => _confirmRemoveGame(store, live)),
              onClose: () => Navigator.of(sheetContext).pop(),
            );
          }),
        );
      },
    );
  }

  /// Confirms and hard-deletes a game from Ludeck.
  ///
  /// This is NOT "Set aside": shelving keeps everything the user recorded and
  /// only hides the game. Removing destroys the game and, by the schema's
  /// cascade, its progress, ownership, placements and rating. There is no
  /// undo, so it is always gated behind a dialog that names the game and says
  /// so plainly.
  Future<void> _confirmRemoveGame(LudeckStore store, TreeItem item) async {
    final title = item.game.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $title?',
            style: Theme.of(context).textTheme.titleMedium),
        content: Text(
          'This deletes $title from Ludeck along with its progress, '
          'rating and where it hangs. It cannot be undone. To keep the '
          'record and only hide it, use "Set aside" instead.',
          style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep it', style: TextStyle(color: Tokens.palette.text)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove', style: TextStyle(color: Tokens.palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.removeGame(item.game.igdbId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed $title from Ludeck.',
            style: TextStyle(color: Tokens.palette.text)),
      ),
    );
  }

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

    // The orchard is the whole app's home. There is no tab bar: Library,
    // Friends and You are quiet icon buttons at the top right, each a pushed
    // screen with its own back arrow, so nothing covers the meadow.
    return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            OrchardView(
              items: items,
              branches: store.branches,
              placements: store.placements,
              onOpenGame: _openStatusSheet,
              onPlantTree: (name) => store.createBranch(name),
              onMoveGame: (item, fromTree, toTree) =>
                  _moveBetweenTrees(store, item, fromTree, toTree),
              // Dragged up from the ground tray. The flight onto the tree is
              // the confirmation, so no snackbar on top of it.
              onFileGame: (item, tree) =>
                  _fileGame(store, item, tree, quiet: true),
              onUnfileGame: (item, tree) => store.unplace(item.game.igdbId, tree),
              onPlay: (item) =>
                  _setProgressAndMaybeRate(store, item, Progress.playing),
              onTreeMenu: (tree, customise) =>
                  _branchMenu(store, tree, customise: customise),
              styles: resolveTreeStyles(
                  treesOf(store.branches).map((b) => b.id).toList(),
                  store.treeStyles),
              onStyleTree: (tree, style) => store.setTreeStyle(tree.id,
                  blossom: style.blossom.name,
                  wood: style.wood.name,
                  decor: style.decorCsv),
              unfiled: _unfiled(items, store),
              addButton: AddMenu(onAction: _onAdd),
              actions: [
                // Share sits beside Settings rather than inside it: sharing
                // your orchard is a headline action, not a preference, and
                // it was buried three taps deep (Settings > You > Share).
                (
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: () => showShareSheet(context),
                  avatar: false,
                ),
                (
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: _openSettings,
                  avatar: false,
                ),
              ],
              bottomInset: Tokens.space.md,
            ),
          ],
        ),
    );
  }

  void _openLibrary() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LibraryScreen(
          onSelect: _openStatusSheet, coverCache: widget.coverCache)));

  void _openFriends() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FriendsScreen()));

  /// The orchard header's Settings button (Share sits beside it). Settings is
  /// where Library, Friends and You live: three separate glass circles read as
  /// a toolbar over the sky and, at a glance, Friends and You were the same
  /// shape. Settings pushes each of them as its own route, unchanged.
  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
            onLibrary: _openLibrary,
            onFriends: _openFriends,
            onProfile: _openProfile,
          )));

  /// The games on no branch (and not shelved), for the orchard's ground pile.
  List<TreeItem> _unfiled(List<TreeItem> items, LudeckStore store) {
    final filed = <int>{
      for (final ids in store.placements.values) ...ids,
    };
    return items
        .where((i) => !i.entry.shelved && !filed.contains(i.game.igdbId))
        .toList();
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

