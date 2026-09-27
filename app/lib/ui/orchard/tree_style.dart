// A tree's look: its blossom, its wood and the props on the ground around it.
//
// Blossom and wood pick one of the baked .riv variants (a palette cannot be
// switched inside one Rive file; rive/tree/build_tree.py BLOSSOMS says why).
// The enum NAMES are the file names, so they must match build_tree.py's
// BLOSSOMS / WOODS keys. Decorations are painted by the app on the meadow
// (orchard_backdrop.dart), not in the file, so they never fight the tree's
// sway or its growth.

import 'package:flutter/material.dart';

import '../tokens.dart';

enum TreeBlossom {
  blossom('Blossom'),
  maple('Maple'),
  jade('Jade'),
  wisteria('Wisteria'),
  frost('Frost');

  const TreeBlossom(this.label);
  final String label;
  Color get swatch => Tokens.orchard.blossom[index];
}

enum TreeWood {
  plum('Plum'),
  oak('Oak'),
  birch('Birch'),
  ebony('Ebony');

  const TreeWood(this.label);
  final String label;
  Color get swatch => Tokens.orchard.wood[index];
}

enum TreeDecor {
  flowers('Flowers', Icons.local_florist_outlined),
  mushrooms('Mushrooms', Icons.spa_outlined),
  stones('Stones', Icons.landscape_outlined),
  fence('Fence', Icons.fence_outlined),
  lantern('Lantern', Icons.light_outlined),
  fireflies('Fireflies', Icons.auto_awesome_outlined);

  const TreeDecor(this.label, this.icon);
  final String label;
  final IconData icon;
}

@immutable
class TreeStyle {
  const TreeStyle({
    required this.blossom,
    required this.wood,
    this.decor = const {},
  });

  final TreeBlossom blossom;
  final TreeWood wood;
  final Set<TreeDecor> decor;

  /// The look of a tree nobody has styled. Trees differ from their
  /// neighbours out of the box: the blossom steps through the palette in
  /// planting order, and every tree starts with a little grass-level life so
  /// the meadow is never bare.
  factory TreeStyle.defaultFor(int treeIndex) => TreeStyle(
        blossom: TreeBlossom.values[treeIndex % TreeBlossom.values.length],
        wood: TreeWood.plum,
        decor: const {TreeDecor.flowers},
      );

  /// Asset for this look's baked tree (rive/tree/build_variants.py).
  String get asset => 'assets/rive/trees/tree_${blossom.name}_${wood.name}.riv';

  TreeStyle copyWith({
    TreeBlossom? blossom,
    TreeWood? wood,
    Set<TreeDecor>? decor,
  }) =>
      TreeStyle(
        blossom: blossom ?? this.blossom,
        wood: wood ?? this.wood,
        decor: decor ?? this.decor,
      );

  /// Storage form: `decor` as a comma list of names. Unknown names are
  /// dropped on read, so a prop removed in a later version cannot break a
  /// saved tree.
  String get decorCsv =>
      (decor.map((d) => d.name).toList()..sort()).join(',');

  static Set<TreeDecor> decorFromCsv(String? csv) {
    if (csv == null || csv.isEmpty) return const {};
    final byName = {for (final d in TreeDecor.values) d.name: d};
    return {
      for (final n in csv.split(','))
        if (byName[n] != null) byName[n]!,
    };
  }

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static TreeStyle fromRow(Map<String, Object?> r) => TreeStyle(
        blossom: _byName(
            TreeBlossom.values, r['blossom'] as String?, TreeBlossom.blossom),
        wood: _byName(TreeWood.values, r['wood'] as String?, TreeWood.plum),
        decor: decorFromCsv(r['decor'] as String?),
      );

  @override
  bool operator ==(Object other) =>
      other is TreeStyle &&
      other.blossom == blossom &&
      other.wood == wood &&
      other.decorCsv == decorCsv;

  @override
  int get hashCode => Object.hash(blossom, wood, decorCsv);
}

/// The blossom [used] has fewest of; ties go to palette order. A new tree
/// takes this, so the orchard fills with every colour before any repeats.
TreeBlossom leastUsedBlossom(Iterable<TreeBlossom> used) {
  final count = {for (final b in TreeBlossom.values) b: 0};
  for (final u in used) {
    count[u] = count[u]! + 1;
  }
  var best = TreeBlossom.values.first;
  for (final b in TreeBlossom.values) {
    if (count[b]! < count[best]!) best = b;
  }
  return best;
}

/// Each tree's look, saved or default. [saved] is the store's raw rows
/// (`LudeckStore.treeStyles`); [treeIds] are the trees in page order, which is
/// what the default steps through, so neighbouring trees differ.
Map<int, TreeStyle> resolveTreeStyles(
    List<int> treeIds, Map<int, Map<String, Object?>> saved) {
  return {
    for (var i = 0; i < treeIds.length; i++)
      treeIds[i]: saved[treeIds[i]] != null
          ? TreeStyle.fromRow(saved[treeIds[i]]!)
          : TreeStyle.defaultFor(i),
  };
}
