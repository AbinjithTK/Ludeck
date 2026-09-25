import 'package:flutter/material.dart';

import 'data/enums.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'services/catalog_service.dart';
import 'services/share_intake.dart';
import 'services/share_resolver.dart';
import 'ui/intake/confirm_sheet.dart';
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
    return MaterialApp(
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
      home: TreeScreen(repo: repo),
    );
  }
}

class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    required this.repo,
    this.intake = const PlatformShareIntake(),
    this.catalog,
  });

  final Repository repo;

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
  /// Null means the first read has not come back yet. It is not the same as an
  /// empty collection, and the two must not render the same way.
  List<TreeItem>? _items;
  Platform? _filter;

  /// How many rows `loadDetailed` could not read on the last load. Zero unless
  /// something is actually wrong. Never hidden: a row that vanishes from the
  /// count without a word is how someone concludes the app lost their data.
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalog = widget.catalog ?? FixtureCatalog();
    _resolver = ShareResolver(catalog: _catalog);
    _load().then((_) => _drainShare());
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

    for (final candidate in choice.accepted) {
      final id = candidate.igdbId;
      if (id == null) continue;

      final game = await _catalog.byId(id);
      if (game == null) continue;

      await widget.repo.upsert(TreeItem(
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

      await widget.repo.addSource(Source(
        igdbId: id,
        url: candidate.link?.uri.toString(),
        kind: r.kind,
        matchMethod: candidate.method,
        addedAt: now,
      ));
    }

    await _load();
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

  Future<void> _load() async {
    final result = await widget.repo.loadDetailed();
    if (!mounted) return;
    setState(() {
      _items = result.items;
      _skipped = result.skipped;
    });
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

  /// Writes through, then re-reads. Optimistic local mutation was the old
  /// behaviour and it is wrong now: the database is the truth, and a write that
  /// silently failed would leave the screen lying about what was saved.
  Future<void> _setProgress(TreeItem item, Progress p) async {
    await widget.repo.setProgress(item.game.igdbId, p);
    await _load();
  }

  Future<void> _setOwnership(TreeItem item, Ownership o) async {
    await widget.repo.setOwnership(item.game.igdbId, o);
    await _load();
  }

  /// Explains a nonzero skipped count when the user taps the notice.
  ///
  /// States what happened, that nothing else was touched, and gives one
  /// concrete thing to do. What it does not do is apologise or speculate about
  /// cause: this is a rare failure mode with one honest description, and
  /// dressing it up as either a disaster or a shrug would both be lies.
  void _showSkippedNotice() {
    final n = _skipped;
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
                    _setProgress(item, p);
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
                    _setOwnership(item, o);
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
    final text = Theme.of(context).textTheme;
    final items = _items;

    // The first read. Deliberately quiet: no spinner, because the read is fast
    // and a spinner that flashes is worse than a moment of nothing.
    if (items == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      // The collection visualisation sits behind the chrome. This is the plain
      // Flutter stand-in for the Rive tree while feature behaviour is built and
      // tested: the tree wedges the Windows test runner and hides per-item
      // status behind a canvas. The chrome layout (header top-left, add-menu
      // bottom-left) is unchanged, so swapping the tree back in later is a
      // one-widget change here.
      body: Stack(
        fit: StackFit.expand,
        children: [
          CollectionView(
            items: items,
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
                        : '${item.game.title} \u00B7 ${item.entry.progress.label}'
                            '${hours == null ? '' : ' \u00B7 $hours h'}',
                    style: TextStyle(color: Tokens.palette.text),
                  ),
                ),
              );
            },
            onHold: _openStatusSheet,
          ),

          // The chrome. Inside a SafeArea so it clears the notch, while the
          // canvas behind it deliberately does not.
          SafeArea(
            child: Stack(
              children: [
                // Top left. Wrapped in IgnorePointer so a drag that happens to
                // begin on the text still rotates the tree. Without this the
                // header becomes a dead patch of screen, which is exactly the
                // kind of thing nobody reports and everybody feels.
                Positioned(
                  left: Tokens.space.md,
                  top: Tokens.space.md,
                  right: Tokens.space.md,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_headline(items), style: text.displaySmall),
                        SizedBox(height: Tokens.space.xxs),
                        Text(_subline(items), style: text.labelSmall),
                      ],
                    ),
                  ),
                ),

                // A separate, tappable notice below the header rather than
                // folded into it. The header is wrapped in IgnorePointer so a
                // drag can start on the text; this is the one line in that
                // corner someone might actually want to act on, so it needs its
                // own hit target rather than inheriting a dead zone.
                //
                // Present only when `_skipped > 0`. Silence is correct in the
                // ordinary case: printing "0 rows could not be read" every time
                // the screen opens would train the user to stop reading this
                // corner, which is exactly wrong the one time it says something
                // real.
                if (_skipped > 0)
                  Positioned(
                    left: Tokens.space.md,
                    top: Tokens.space.md + Tokens.space.xl + Tokens.space.lg,
                    right: Tokens.space.md,
                    child: GestureDetector(
                      onTap: _showSkippedNotice,
                      child: Text(
                        _skipped == 1
                            ? '1 game could not be read. Tap to find out more.'
                            : '$_skipped games could not be read. Tap to find '
                                'out more.',
                        style: text.labelSmall
                            ?.copyWith(color: Tokens.palette.danger),
                      ),
                    ),
                  ),

                // Bottom left, per the reference. The add action is the one
                // thing a new person has to find, so it sits where a thumb
                // already rests.
                Positioned(
                  left: Tokens.space.md,
                  bottom: Tokens.space.md,
                  child: AddMenu(onAction: _onAdd),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
