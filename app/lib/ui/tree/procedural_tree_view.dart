// The procedural tree on screen: painted wood, real cover art hanging on it.
//
// This is the ONE renderer. It replaces three that existed at once -- the home
// screen's `BranchingTreeView` (left/right rows keyed on branches, which drew
// nothing at all when the user had no branches), the profile's Rive `TreeScene`
// (five parallaxing artboards keyed on owned PLATFORMS, a different tree from the
// same data), and `CollectionView` (a list, which remains as the deliberate
// list-shaped alternative and is not a tree at all).
//
// THE ONE STRUCTURAL DECISION HERE
//
// The wood is painted and the games are WIDGETS on top of it. Not one or the
// other, and the split is not arbitrary:
//
//   * Wood, foliage and ground have no identity and no interaction, so painting
//     them is free -- one canvas, no widget tree, no layout pass.
//   * A game is identified by its cover art and must be tappable and
//     announceable. A painted circle cannot show a cover, cannot be focused by a
//     screen reader and cannot host a network image. The previous portrait
//     painted games as grey spheres while the tray 200px below showed the real
//     art, which threw away the single most identifiable thing about a game
//     exactly where identity matters most.
//
// So each fruit is a real `GameNode` -- the same widget the list rows use, so
// cover lookup, the initials placeholder, the harvest glow, the arrival
// animation and the spoken label are shared rather than reimplemented here.
//
// NO ROTATION, no orbit, no idle drift. `DESIGN.md` §7 rejects ambient tree
// motion outright, and the user judged the rotating tree worse than a still one.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../map/game_node.dart';
import '../tokens.dart';
import 'procedural_tree.dart';
import 'tree_painter.dart';

class ProceduralTreeView extends StatefulWidget {
  const ProceduralTreeView({
    super.key,
    required this.items,
    this.branches = const [],
    this.placements = const {},
    this.onSelect,
    this.onHold,
    this.coverCache,
    this.onCoverFound,
    this.topInset = 0,
    this.bottomInset = 0,
    this.showGround = true,
    this.animateArrivals = true,
  });

  final List<TreeItem> items;

  /// The user's own branches, in the user's own order.
  final List<Branch> branches;

  /// branchId -> the igdbIds hanging on it.
  final Map<int, List<int>> placements;

  /// Null on the profile portrait, where the tree is a picture of the
  /// collection rather than a control. Passing null also removes every gesture,
  /// so the portrait cannot be half-interactive.
  final ValueChanged<TreeItem>? onSelect;
  final ValueChanged<TreeItem>? onHold;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  final double topInset;
  final double bottomInset;

  /// The ground mound. Off for a small portrait, where a horizon crops badly.
  final bool showGround;

  /// False in layout tests, so a fruit is at final size on the first pump.
  final bool animateArrivals;

  @override
  State<ProceduralTreeView> createState() => _ProceduralTreeViewState();
}

class _ProceduralTreeViewState extends State<ProceduralTreeView> {
  /// Ids present at the last build. Null only before the first, which is what
  /// stops the whole existing collection animating on app open -- `DESIGN.md` §7
  /// is explicit that growth plays when something is added and never otherwise.
  Set<int>? _seen;
  Set<int> _arriving = const {};

  @override
  void initState() {
    super.initState();
    _seen = {for (final i in widget.items) i.game.igdbId};
  }

  @override
  void didUpdateWidget(ProceduralTreeView old) {
    super.didUpdateWidget(old);
    final current = {for (final i in widget.items) i.game.igdbId};
    _arriving = widget.animateArrivals
        ? current.difference(_seen ?? const <int>{})
        : const <int>{};
    _seen = current;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          constraints.maxHeight - widget.topInset - widget.bottomInset,
        );
        if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();

        // Scale off the WIDTH, so the same tree is proportionally identical on a
        // 412pt phone and in a 150pt portrait. Tying it to height instead would
        // make the portrait's fruit huge, since a portrait is much shorter than
        // it is narrow-relative-to-a-phone.
        final scale = (size.width / 412).clamp(0.28, 1.6);
        final fruitRadius = (Tokens.size.fruit / 2) * scale;

        final tree = ProceduralTree.build(
          canvas: size,
          branches: widget.branches,
          placements: widget.placements,
          items: widget.items,
          fruitRadius: fruitRadius,
          trunkWidth: Tokens.size.trunk * scale,
        );

        final interactive = widget.onSelect != null || widget.onHold != null;
        final branchNames = {for (final b in widget.branches) b.id: b.name};

        return Padding(
          padding: EdgeInsets.only(
            top: widget.topInset,
            bottom: widget.bottomInset,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    // Foliage is generated OUTSIDE the painter and passed in, so
                    // the same canopy is reused across repaints instead of being
                    // regenerated on every frame the painter runs.
                    painter: ProceduralTreePainter(
                      tree: tree,
                      foliage: foliageFor(tree),
                      groundVisible: widget.showGround,
                    ),
                  ),
                ),
              ),

              // Far fruit first, so a nearer cover overlaps it rather than the
              // other way round. Paint order is the depth cue.
              for (final fruit in _depthSorted(tree))
                _positioned(
                  fruit: fruit,
                  child: GameNode(
                    key: ValueKey('fruit-${fruit.item.game.igdbId}-${fruit.branchId}'),
                    item: fruit.item,
                    cardWidth: fruit.radius * 2,
                    showTitle: false,
                    branchName: branchNames[fruit.branchId],
                    animateIn: _arriving.contains(fruit.item.game.igdbId),
                    coverCache: widget.coverCache,
                    onCoverFound: widget.onCoverFound,
                    onTap: () => widget.onSelect?.call(fruit.item),
                    onLongPress: widget.onHold == null
                        ? null
                        : () => widget.onHold!.call(fruit.item),
                  ),
                  interactive: interactive,
                ),

              // There is no soil strip any more. Recommendations are buds in the
              // list above -- smaller cards on the wood -- so they go through the
              // same depth sort, the same stalk and the same tap target as
              // everything else instead of living in a separate bar underneath.
            ],
          ),
        );
      },
    );
  }

  /// Furthest first.
  List<TreeFruit> _depthSorted(ProceduralTree tree) {
    final all = tree.allFruit.toList()
      ..sort((a, b) => b.depth.compareTo(a.depth));
    return all;
  }

  Widget _positioned({
    required TreeFruit fruit,
    required Widget child,
    required bool interactive,
  }) {
    final width = fruit.radius * 2;
    final height = width * Tokens.size.coverRatio;

    // A small deterministic tilt, from the game's own id. A grid of perfectly
    // upright cards reads as a contact sheet pasted onto a tree; a few degrees
    // of lean reads as something hanging. Derived from the id rather than a
    // random so a game's tilt never changes between launches.
    final tilt = ((fruit.item.game.igdbId % 7) - 3) * 0.022;

    return Positioned(
      left: fruit.centre.dx - width / 2,
      top: fruit.centre.dy - height / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Transform.rotate(
          angle: tilt,
          // The stalk meets the top edge, so that is what the card swings from.
          alignment: Alignment.topCenter,
          child: Opacity(
            // Set-back fruit loses a little contrast, the same aerial
            // perspective the foliage uses. Never below 0.78: this is a depth
            // cue, not a "less important" signal, and every game on the tree is
            // equally the user's.
            opacity: 1 - fruit.depth * 0.16,
            child: child,
          ),
        ),
      ),
    );
  }
}
