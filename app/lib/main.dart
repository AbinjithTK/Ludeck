import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/enums.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'services/catalog_service.dart';
import 'services/share_intake.dart';
import 'services/share_resolver.dart';
import 'state/ludeck_store.dart';
import 'ui/intake/confirm_sheet.dart';
import 'ui/chrome_metrics.dart';
import 'ui/tokens.dart';
import 'ui/shell/add_menu.dart';
import 'ui/collection/collection_view.dart';

Future<void> main() async {
  // Required before any plugin call, and Repository.open touches path_provider.
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repository.open();
  runApp(LudeckApp(repo: repo));
}

class LudeckApp extends StatelessWidget {
  const LudeckApp({super.key, required this.repo});

  final Repository repo;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.type;
    // The store is created here, above MaterialApp, so it outlives any route
    // and a sheet pushed on top of the screen reads the same state the screen
    // does.
    return ChangeNotifierProvider<LudeckStore>(
      create: (_) => LudeckStore(repo)..load(),
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
      home: TreeScreen(),
      ),
    );
  }
}

class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    this.intake = const PlatformShareIntake(),
    this.catalog,
  });

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
  /// Only view state lives here now. The collection, the skipped count, the
  /// loading flag and the error all belong to `LudeckStore`, which is read from
  /// the provider. A screen holding both a Repository and a store would be two
  /// sources of truth for the same rows.
  Platform? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalog = widget.catalog ?? FixtureCatalog();
    _resolver = ShareResolver(catalog: _catalog);
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

      await store.upsert(TreeItem(
        game: game,
        entry: Entry(
          igdbId: id,
          // A share is a recommendation, not a purchase. Ownership and progress
          // are separate axes and neither is implied by the other.
          ownership: Ownership.spotted,
          progress: Progress.untouched,
          recommendedBy: choice.recommendedBy,
        ),
        copies: const [],
      ));

      await store.addSource(Source(
        igdbId: id,
        url: candidate.link?.uri.toString(),
        kind: r.kind,
        matchMethod: candidate.method,
        addedAt: now,
      ));
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

  /// The headline. It counts what exists, never what is outstanding.
  ///
  /// Ripeness used to be the headline. It is gone on purpose: completion is the
  /// only status signal now. A count of what is on the tree can only go up,
  /// which is the whole difference between this and a backlog.
  String _headline(List<TreeItem> items) {
    if (items.isEmpty) return 'Nothing planted yet.';
    final onTree = items.where((i) => !i.isSeed).length;
    if (onTree == 0) return 'Seeds only, for now.';
    if (onTree == 1) return 'One on the tree.';
    return '$onTree on the tree.';
  }

  /// The second line. A part that is zero is left out rather than printed as a
  /// zero, because "0 harvested" reads as a reproach and an omission does not.
  String _subline(List<TreeItem> items) {
    final seeds = items.where((i) => i.isSeed).length;
    final harvested = items.where((i) => i.isHarvested).length;
    final parts = <String>[
      if (harvested > 0) '$harvested harvested',
      if (seeds > 0) '$seeds ${seeds == 1 ? 'seed' : 'seeds'}',
      if (_filter != null) _filter!.label,
    ];
    return parts.join(' \u00B7 ');
  }

  /// Nothing here is connected to a catalogue yet, and the honest thing is to
  /// say so in plain words rather than open a search box that cannot return
  /// anything. The affordance is real; the source behind it is not there.
  void _onAdd(AddAction action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Tokens.palette.surface,
        duration: const Duration(seconds: 3),
        content: Text(
          'The game catalogue is not connected yet, so '
          '"${action.label.toLowerCase()}" has nothing to look in.',
          style: TextStyle(color: Tokens.palette.text),
        ),
      ),
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
                    store.setProgress(item.game.igdbId, p);
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
      body: Column(
        // Stretch, not the default centre. A Column centres its children on the
        // cross axis, which shrink-wraps the header to its text width and centres
        // the block -- the header is specified top-LEFT.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            headline: _headline(items),
            subline: _subline(items),
            skipped: store.skipped,
            onSkippedTap: _showSkippedNotice,
          ),

          // The content layer, with the add control floating over it. Only this
          // part is a Stack, so nothing can overlap the header.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CollectionView(
                  items: items,
                  // The header already supplies the gap above; the list only
                  // needs to clear the control at the bottom.
                  topInset: 0,
                  bottomInset: chrome.bottom,
                  onSelect: (item) {
                    final hours = item.game.hours;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Tokens.palette.surface,
                        duration: const Duration(seconds: 2),
                        content: Text(
                          item.isSeed
                              ? '${item.game.title} \u00B7 seed from '
                                  '${item.entry.recommendedBy ?? "somewhere"}'
                              : '${item.game.title} \u00B7 '
                                  '${item.entry.progress.label}'
                                  '${hours == null ? '' : ' \u00B7 $hours h'}',
                          style: TextStyle(color: Tokens.palette.text),
                        ),
                      ),
                    );
                  },
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
class _Header extends StatelessWidget {
  const _Header({
    required this.headline,
    required this.subline,
    required this.skipped,
    required this.onSkippedTap,
  });

  final String headline;
  final String subline;
  final int skipped;
  final VoidCallback onSkippedTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      // Only the top edge: the content below owns the bottom inset.
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Tokens.space.md,
          Tokens.space.md,
          Tokens.space.md,
          Tokens.space.lg,
        ),
        child: Column(
          key: const Key('screen-header'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(headline, style: text.displaySmall),
            SizedBox(height: Tokens.space.xxs),
            Text(subline, style: text.labelSmall),

            // Present only when something actually failed to read. Silence is
            // correct in the ordinary case: printing "0 rows could not be read"
            // every time the screen opens would train the user to stop reading
            // this corner, which is exactly wrong the one time it says something
            // real.
            //
            // It flows after the subline rather than being positioned at a fixed
            // offset, so it can no longer land on top of a wrapped headline.
            if (skipped > 0) ...[
              SizedBox(height: Tokens.space.xs),
              GestureDetector(
                onTap: onSkippedTap,
                child: Text(
                  skipped == 1
                      ? '1 game could not be read. Tap to find out more.'
                      : '$skipped games could not be read. Tap to find out '
                          'more.',
                  style:
                      text.labelSmall?.copyWith(color: Tokens.palette.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A fade at the bottom edge, so rows dissolve rather than sliding visibly
/// behind the add control while the list is being dragged.
///
/// Opaque at the screen edge and transparent at its inner edge. Sized from the
/// same `ChromeMetrics.bottom` the list pads itself by, so the covered band and
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
