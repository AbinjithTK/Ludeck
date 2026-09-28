// The home tree as a canopy you zoom into (mockup B, chosen in Stage 2).
//
// One level at a time: the trunk rises from the bottom, the current branch's
// sub-branches fan up from a single fork with their names on them, and the
// games show as small covers at each tip. Tapping a branch zooms into it, so it
// becomes the trunk and its own sub-branches fan the same way; the breadcrumb
// zooms back out. A branch with no sub-branches fans its games instead.
//
// Lives beside the roadmap rather than replacing it (`RoadmapView` is kept and
// reachable from the view switch) so the old home is one tap away while this
// one earns its place on a device.
//
// Geometry is `canopy_layout.dart` (pure, tested); paint is
// `canopy_painter.dart`; this file is only the interactive shell.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/branch_tree.dart';
import '../../services/cover_art_cache.dart';
import '../map/game_node.dart';
import '../tokens.dart';
import 'canopy_layout.dart';
import 'canopy_painter.dart';

class CanopyView extends StatefulWidget {
  const CanopyView({
    super.key,
    required this.items,
    required this.branches,
    required this.placements,
    this.unfiledCount = 0,
    this.coverCache,
    this.onCoverFound,
    this.onSelect,
    this.onHold,
    this.onCreateBranch,
    this.onBranchHold,
    this.onPick,
    this.onUnfiledTap,
    this.onSwitchView,
    this.bottomInset = 0,
    this.rightInset = 0,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;

  /// Games on no branch. Shown as a tray pill at the root so new finds are
  /// never silently lost; tapping it is [onUnfiledTap].
  final int unfiledCount;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  final ValueChanged<TreeItem>? onSelect;
  final ValueChanged<TreeItem>? onHold;

  /// Grow a new branch under [parentId] (`null` = from the trunk).
  final ValueChanged<int?>? onCreateBranch;

  /// Long-press on a branch name: rename, move, delete live there.
  final ValueChanged<Branch>? onBranchHold;

  /// "What should I play?" with the games in view. [from] is null at the root.
  final void Function(List<TreeItem> pool, Branch? from)? onPick;

  final VoidCallback? onUnfiledTap;

  /// Switch to the roadmap (path) view.
  final VoidCallback? onSwitchView;

  /// Band at the bottom the controls must clear (the navigation pill).
  final double bottomInset;

  /// Width at the bottom right the controls must leave (the add button).
  final double rightInset;

  @override
  State<CanopyView> createState() => CanopyViewState();
}

class CanopyViewState extends State<CanopyView> {
  /// The zoom path, root first. Empty = the whole tree.
  final List<int> _path = [];

  /// Which way the last zoom went, so the transition reads as in or out.
  bool _zoomingIn = true;

  int? get focus => _path.isEmpty ? null : _path.last;

  void zoomTo(int? branchId, BranchTree tree) => setState(() {
        _zoomingIn = branchId != null &&
            (focus == null || tree.pathTo(branchId).any((b) => b.id == focus));
        _path
          ..clear()
          ..addAll(branchId == null
              ? const <int>[]
              : tree.pathTo(branchId).map((b) => b.id));
      });

  @override
  Widget build(BuildContext context) {
    final tree = BranchTree(widget.branches, widget.placements);
    // A branch deleted or moved elsewhere while zoomed: fall back to the
    // deepest part of the path that still exists, never to an empty screen.
    while (_path.isNotEmpty && tree[_path.last] == null) {
      _path.removeLast();
    }
    if (_path.isNotEmpty) {
      final real = tree.pathTo(_path.last).map((b) => b.id).toList();
      if (real.join(',') != _path.join(',')) {
        _path
          ..clear()
          ..addAll(real);
      }
    }

    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final focusBranch = focus == null ? null : tree[focus!];

    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      const topBar = 48.0;
      final controls = Tokens.size.control + Tokens.space.md * 2;
      final bottomClear = widget.bottomInset + controls +
          (focus == null && !tree.isEmpty && widget.unfiledCount > 0 ? 36 : 0);

      final live = [
        for (final i in widget.items)
          if (!i.entry.shelved) i.game.igdbId,
      ];
      // No branches AND no games: the first-run screen. No branches but some
      // games: the games hang on the trunk, with a one-line nudge to group them.
      final bare = tree.isEmpty;
      if (bare && live.isEmpty) {
        return _EmptyCanopy(
          size: size,
          bottomClear: bottomClear,
          onCreate: widget.onCreateBranch == null
              ? null
              : () => widget.onCreateBranch!(null),
          unfiledCount: widget.unfiledCount,
          onSwitchView: widget.onSwitchView,
        );
      }

      final layout = CanopyLayout.build(tree, focus, size,
          topClear: topBar + (bare ? 40 : 0),
          bottomClear: bottomClear,
          trunkGames: bare ? live : const []);

      final drawing = KeyedSubtree(
        key: ValueKey('canopy-${focus ?? 'root'}'),
        child: _Level(
          layout: layout,
          byId: byId,
          coverCache: widget.coverCache,
          onCoverFound: widget.onCoverFound,
          onSelect: widget.onSelect,
          onHold: widget.onHold,
          onOpen: (b) => zoomTo(b.id, tree),
          onBranchHold: widget.onBranchHold,
          onMore: () => _showOverflow(context, tree, byId,
              shownGames: layout.gameTwigs.length, trunkGames: bare ? live : null),
        ),
      );

      final pool = focus == null
          ? widget.items.where((i) => !i.entry.shelved).toList()
          : [
              for (final id in tree.gamesUnder(focus!))
                if (byId[id] != null) byId[id]!,
            ];

      return Stack(children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: reduce ? Duration.zero : Tokens.motion.grow,
            switchInCurve: Tokens.motion.easeOut,
            switchOutCurve: Tokens.motion.easeOut,
            transitionBuilder: (child, anim) {
              final incoming = child.key == drawing.key;
              // Zooming in: the new level grows from slightly small, the old one
              // swells past the camera. Out is the mirror. Anchored low, at the
              // trunk, because that is where the eye travels from.
              final from = incoming
                  ? (_zoomingIn ? .86 : 1.12)
                  : (_zoomingIn ? 1.12 : .86);
              return FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  alignment: const Alignment(0, .6),
                  scale: Tween(begin: from, end: 1.0).animate(anim),
                  child: child,
                ),
              );
            },
            child: drawing,
          ),
        ),
        if (bare)
          Positioned(
            left: Tokens.space.md,
            right: Tokens.space.md,
            top: topBar + Tokens.space.xxs,
            child: Text(
              'These hang on the trunk. Grow a branch to group them by mood, '
              'length or who you play with.',
              style: _caption(colour: Tokens.palette.textDim),
            ),
          ),
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md,
          top: Tokens.space.xs,
          child: _TopBar(
            path: [for (final id in _path) tree[id]!],
            onCrumb: (id) => zoomTo(id, tree),
            onSwitchView: widget.onSwitchView,
          ),
        ),
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md + widget.rightInset,
          bottom: widget.bottomInset + Tokens.space.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (focus == null && !bare && widget.unfiledCount > 0) ...[
                _Pill(
                  label: widget.unfiledCount == 1
                      ? '1 new game · tap to file'
                      : '${widget.unfiledCount} new games · tap to file',
                  dashed: true,
                  onTap: widget.onUnfiledTap,
                ),
                SizedBox(height: Tokens.space.xs),
              ],
              Row(children: [
                Expanded(
                  child: _PrimaryButton(
                    label: focusBranch == null
                        ? 'What should I play?'
                        : 'Pick one from here',
                    onTap: pool.isEmpty || widget.onPick == null
                        ? null
                        : () => widget.onPick!(pool, focusBranch),
                  ),
                ),
                SizedBox(width: Tokens.space.xs),
                _SecondaryButton(
                  // Same words at every level: here, a new branch grows inside the one
                  // in view, which the breadcrumb already names.
                  label: '+ Branch',
                  onTap: widget.onCreateBranch == null
                      ? null
                      : () => widget.onCreateBranch!(focus),
                ),
              ]),
            ],
          ),
        ),
      ]);
    });
  }

  void _showOverflow(
      BuildContext context, BranchTree tree, Map<int, TreeItem> byId,
      {required int shownGames, List<int>? trunkGames}) {
    final kids = tree.childrenOf(focus);
    final hidden = kids.length > kMaxFanned
        ? kids.skip(kMaxFanned - 1).toList()
        : const <Branch>[];
    final games = kids.isNotEmpty
        ? const <int>[]
        : (focus != null ? tree.gamesOn(focus!) : (trunkGames ?? const <int>[]))
            .skip(shownGames)
            .toList();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final b in hidden)
            ListTile(
              title: Text(b.name),
              trailing: Text('${tree.gamesUnder(b.id).length}',
                  style: TextStyle(color: Tokens.palette.textDim)),
              onTap: () {
                Navigator.of(sheet).pop();
                zoomTo(b.id, tree);
              },
            ),
          for (final id in games)
            if (byId[id] != null)
              ListTile(
                title: Text(byId[id]!.game.title),
                onTap: () {
                  Navigator.of(sheet).pop();
                  widget.onSelect?.call(byId[id]!);
                },
              ),
        ]),
      ),
    );
  }
}

/// One level's drawing plus the tappable things on it.
class _Level extends StatelessWidget {
  const _Level({
    required this.layout,
    required this.byId,
    required this.onOpen,
    required this.onMore,
    this.coverCache,
    this.onCoverFound,
    this.onSelect,
    this.onHold,
    this.onBranchHold,
  });

  final CanopyLayout layout;
  final Map<int, TreeItem> byId;
  final ValueChanged<Branch> onOpen;
  final VoidCallback onMore;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;
  final ValueChanged<TreeItem>? onSelect;
  final ValueChanged<TreeItem>? onHold;
  final ValueChanged<Branch>? onBranchHold;

  Widget _cover(int id, Offset at, Size chip) {
    final item = byId[id];
    if (item == null) return const SizedBox.shrink();
    return Positioned(
      left: at.dx - chip.width / 2,
      top: at.dy - chip.height / 2,
      width: chip.width,
      child: GameNode(
        item: item,
        cardWidth: chip.width,
        showTitle: false,
        coverCache: coverCache,
        onCoverFound: onCoverFound,
        onTap: () => onSelect?.call(item),
        onLongPress: onHold == null ? null : () => onHold!(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: CustomPaint(painter: CanopyPainter(layout)),
        ),
      ),
      for (final f in layout.fans)
        for (var k = 0; k < f.preview.length; k++)
          _cover(f.preview[k], f.previewAt[k], layout.chip),
      for (final g in layout.gameTwigs) _cover(g.igdbId, g.at, layout.chip),
      for (final f in layout.fans)
        _Centered(
          at: f.label,
          child: _BranchLabel(
            name: f.branch.name,
            count: f.gameCount,
            subCount: f.subCount,
            onTap: () => onOpen(f.branch),
            onLongPress:
                onBranchHold == null ? null : () => onBranchHold!(f.branch),
          ),
        ),
      if (layout.moreAt != null)
        _Centered(
          at: layout.moreAt!,
          child: _Pill(label: '+${layout.more}', onTap: onMore),
        ),
    ]);
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.at, required this.child});
  final Offset at;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
        left: at.dx,
        top: at.dy,
        child: FractionalTranslation(
          translation: const Offset(-.5, -.5),
          child: child,
        ),
      );
}

TextStyle _caption({bool bold = false, Color? colour}) => TextStyle(
      fontSize: Tokens.type.caption,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: colour ?? Tokens.palette.text,
      height: 1.2,
    );

class _BranchLabel extends StatelessWidget {
  const _BranchLabel({
    required this.name,
    required this.count,
    required this.subCount,
    required this.onTap,
    this.onLongPress,
  });
  final String name;
  final int count, subCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final games = count == 1 ? '1 game' : '$count games';
    final subs = subCount == 0
        ? ''
        : (subCount == 1 ? ', 1 sub-branch' : ', $subCount sub-branches');
    return Semantics(
      button: true,
      label: '$name, $games$subs. Opens this branch.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Enlarges the hit area past the painted pill.
          padding: EdgeInsets.all(Tokens.space.xs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Tokens.cosmos.panelDeep,
                borderRadius: BorderRadius.circular(Tokens.radius.pill),
                border: Border.all(color: Tokens.cosmos.panelEdge),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Tokens.space.sm, vertical: Tokens.space.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _caption(bold: true)),
                  ),
                  SizedBox(width: Tokens.space.xxs),
                  Text('$count',
                      style: _caption(colour: Tokens.palette.textDim)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.onTap, this.dashed = false});
  final String label;
  final VoidCallback? onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Tokens.cosmos.panelDeep,
              borderRadius: BorderRadius.circular(Tokens.radius.pill),
              border: Border.all(
                  color: dashed
                      ? Tokens.canopy.foliageLit
                      : Tokens.cosmos.panelEdge),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Tokens.space.sm, vertical: Tokens.space.xs),
              child: Text(label, style: _caption(bold: true)),
            ),
          ),
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: Tokens.size.control,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.canopy.foliageNear,
            foregroundColor: Tokens.palette.bg,
            disabledBackgroundColor: Tokens.cosmos.panel,
            shape: const StadiumBorder(),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: Tokens.type.body, fontWeight: FontWeight.w700),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: Tokens.size.control,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Tokens.palette.text,
            backgroundColor: Tokens.cosmos.panel,
            side: BorderSide(color: Tokens.cosmos.panelEdge),
            shape: const StadiumBorder(),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: Tokens.type.caption, fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.path, required this.onCrumb, this.onSwitchView});
  final List<Branch> path;
  final ValueChanged<int?> onCrumb;
  final VoidCallback? onSwitchView;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (path.isNotEmpty)
        IconButton(
          tooltip: 'Back out',
          onPressed: () =>
              onCrumb(path.length > 1 ? path[path.length - 2].id : null),
          icon: Icon(Icons.arrow_back, color: Tokens.palette.text),
        ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(children: [
            if (path.isNotEmpty) _Crumb(
              label: 'My tree',
              current: path.isEmpty,
              onTap: path.isEmpty ? null : () => onCrumb(null),
            ),
            for (var i = 0; i < path.length; i++) ...[
              Text(' › ', style: _caption(colour: Tokens.palette.textDim)),
              _Crumb(
                label: path[i].name,
                current: i == path.length - 1,
                onTap: i == path.length - 1 ? null : () => onCrumb(path[i].id),
              ),
            ],
          ]),
        ),
      ),
      if (onSwitchView != null)
        TextButton.icon(
          onPressed: onSwitchView,
          icon: Icon(Icons.timeline, size: 16, color: Tokens.palette.textDim),
          label: Text('Path view',
              style: _caption(colour: Tokens.palette.textDim)),
        ),
    ]);
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.current, this.onTap});
  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
          child: Text(
            label,
            style: current
                ? TextStyle(
                    fontFamily: Tokens.type.displayFamily,
                    fontSize: Tokens.type.title,
                    fontWeight: FontWeight.w700,
                    color: Tokens.palette.text)
                : _caption(colour: Tokens.palette.textDim),
          ),
        ),
      );
}

/// First run, or every branch deleted: a bare sapling that says what a branch
/// is and offers exactly one thing to do.
class _EmptyCanopy extends StatelessWidget {
  const _EmptyCanopy({
    required this.size,
    required this.bottomClear,
    required this.unfiledCount,
    this.onCreate,
    this.onSwitchView,
  });
  final Size size;
  final double bottomClear;
  final int unfiledCount;
  final VoidCallback? onCreate;
  final VoidCallback? onSwitchView;

  @override
  Widget build(BuildContext context) {
    final layout = CanopyLayout.build(BranchTree(const []), null, size,
        topClear: size.height * .35, bottomClear: bottomClear);
    return Stack(children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: CustomPaint(painter: CanopyPainter(layout)),
        ),
      ),
      Positioned(
        left: Tokens.space.lg,
        right: Tokens.space.lg,
        top: Tokens.space.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grow your first branch',
                style: TextStyle(
                    fontFamily: Tokens.type.displayFamily,
                    fontSize: Tokens.type.title,
                    fontWeight: FontWeight.w700,
                    color: Tokens.palette.text)),
            SizedBox(height: Tokens.space.xs),
            Text(
              'A branch is a group of games you would play in the same mood, '
              'like "Couch co-op" or "Under 30 minutes". Branches can hold '
              'smaller branches, and a game can hang on more than one.',
              style: TextStyle(
                  fontSize: Tokens.type.body,
                  color: Tokens.palette.textDim,
                  height: 1.45),
            ),
            if (unfiledCount > 0) ...[
              SizedBox(height: Tokens.space.sm),
              Text(
                unfiledCount == 1
                    ? '1 game is waiting for a branch.'
                    : '$unfiledCount games are waiting for a branch.',
                style: _caption(bold: true, colour: Tokens.canopy.foliageLit),
              ),
            ],
            SizedBox(height: Tokens.space.md),
            _PrimaryButton(label: 'Grow a branch', onTap: onCreate),
            if (onSwitchView != null)
              TextButton(
                onPressed: onSwitchView,
                child: Text('See my games as a path instead',
                    style: _caption(colour: Tokens.palette.textDim)),
              ),
          ],
        ),
      ),
    ]);
  }
}
