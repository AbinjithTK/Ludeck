// Renders NodeTreeView to PNGs in docs/shots so the node outline can be JUDGED
// from pixels. Loads real Roboto so labels render as text, not the test-font
// squares. Run: flutter test test/node_tree_capture_test.dart

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/ui/nodetree/node_tree_layout.dart';
import 'package:ludeck/ui/nodetree/node_tree_view.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:path/path.dart' as p;

Branch br(int id, String name, {int? parent, int order = 0, bool collapsed = false}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: collapsed);

TreeItem game(int id, String title,
        {Progress progress = Progress.untouched,
        Ownership own = Ownership.owned}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(igdbId: id, ownership: own, progress: progress),
      copies: const [],
    );

final branches = [
  br(1, 'Chill nights', order: 0),
  br(2, 'Story nights', order: 1),
  br(3, 'Couch co-op', order: 2),
  br(31, 'With Sam', parent: 3, order: 0),
  br(32, 'Party', parent: 3, order: 1),
  br(4, '20-minute games', order: 3),
];
final placements = {
  1: [101, 102, 103],
  2: [105, 106],
  31: [108, 109],
  32: [110, 111],
  4: [113, 114],
};
final items = [
  game(101, 'Stardew Valley', progress: Progress.playing),
  game(102, 'Unpacking', progress: Progress.finished),
  game(103, 'A Short Hike'),
  game(105, 'Outer Wilds', progress: Progress.finished),
  game(106, 'Disco Elysium'),
  game(108, 'It Takes Two'),
  game(109, 'Deep Rock Galactic', progress: Progress.playing),
  game(110, 'Overcooked 2'),
  game(111, 'Jackbox Party Pack 9'),
  game(113, 'Hades', progress: Progress.playing),
  game(114, 'Balatro'),
];

Future<void> loadRoboto() async {
  var dir = p.dirname(io.Platform.resolvedExecutable);
  while (!io.Directory(p.join(dir, 'material_fonts')).existsSync() &&
      p.dirname(dir) != dir) {
    dir = p.dirname(dir);
  }
  final fonts = p.join(dir, 'material_fonts');
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-bold.ttf', 'roboto-medium.ttf']) {
    final file = io.File(p.join(fonts, f));
    if (file.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await loader.load();
  final icons = io.File(p.join(fonts, 'materialicons-regular.otf'));
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

void main() {
  const phone = Size(390, 780);

  Future<void> capture(WidgetTester tester, String name,
      {List<Branch>? bs,
      Map<int, List<int>>? pl,
      List<TreeItem>? it,
      int unfiled = 0}) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = phone * 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await loadRoboto();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Tokens.cosmos.deep,
                ),
              ),
              child: NodeTreeView(
                items: it ?? items,
                branches: bs ?? branches,
                placements: pl ?? placements,
                unfiledCount: unfiled,
                onSelect: (_) {},
                onCreateBranch: (_) {},
                onToggleCollapse: (_) {},
                onPick: (_, _) {},
                onSwitchView: () {},
                bottomInset: 72,
                rightInset: 64,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = io.Directory('../docs/shots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = io.File('${dir.path}/nodetree-$name.png')
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.existsSync(), isTrue);
    });
  }

  testWidgets('root — branches, sub-branches, games',
      (t) => capture(t, 'root', unfiled: 3));
  testWidgets('nested — Couch co-op expanded with sub-branches',
      (t) => capture(t, 'nested'));
  testWidgets('few — one branch, a few games', (t) => capture(t, 'few', bs: [
        br(1, 'Chill nights'),
      ], pl: {
        1: [101, 102, 103]
      }));
  testWidgets('overflow — many branches', (t) => capture(t, 'overflow', bs: [
        for (var i = 1; i <= 8; i++)
          br(i, ['Chill', 'Story', 'Co-op', 'Short', 'Horror', 'Racing', 'Retro', 'Someday'][i - 1], order: i),
      ], pl: {
        for (var i = 1; i <= 8; i++) i: [100 + (i % 11) + 1],
      }));
  testWidgets('empty — first run',
      (t) => capture(t, 'empty', bs: const [], pl: const {}, it: const []));

  group('layout rules', () {
    final tree = BranchTree(branches, placements);

    test('flatten yields branches before their games, honouring collapse', () {
      final rows = flattenTree(tree);
      expect(rows.first.isBranch, isTrue);
      expect(rows.first.branch!.name, 'Chill nights');
      expect(rows[1].isGame, isTrue);
      final coop = rows.indexWhere((r) => r.branch?.name == 'Couch co-op');
      final withSam = rows.indexWhere((r) => r.branch?.name == 'With Sam');
      expect(withSam > coop, isTrue);
    });

    test('a collapsed branch hides its descendants', () {
      final full = flattenTree(tree).length;
      final folded = flattenTree(tree, collapsedIds: {3}).length;
      expect(folded, full - 6);
    });

    test('childCount counts games under a branch and its sub-branches once', () {
      final rows = flattenTree(tree);
      final coop = rows.firstWhere((r) => r.branch?.name == 'Couch co-op');
      expect(coop.childCount, 4);
    });

    test('poolFor a branch draws every game under it, each once', () {
      expect(poolFor(tree, 3).toSet(), {108, 109, 110, 111});
      expect(poolFor(tree, null).length, greaterThanOrEqualTo(7));
    });

    test('last child is flagged for the connector rail', () {
      final rows = flattenTree(tree, collapsedIds: {3});
      final g103 = rows.firstWhere((r) => r.gameId == 103);
      expect(g103.isLastChild, isTrue);
      final g101 = rows.firstWhere((r) => r.gameId == 101);
      expect(g101.isLastChild, isFalse);
    });
  });
}
