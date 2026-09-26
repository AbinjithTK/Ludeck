// Renders CanopyView to PNGs in docs/shots so it can be JUDGED from pixels,
// plus the layout rules that can be asserted without looking.
//
// Loads real Roboto from the Flutter SDK so labels render as text rather than
// the test font's squares; without it the captures cannot show whether names
// fit. Run: flutter test test/canopy_capture_test.dart

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/ui/canopy/canopy_layout.dart';
import 'package:ludeck/ui/canopy/canopy_view.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:path/path.dart' as p;

Branch br(int id, String name, {int? parent, int order = 0}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: false);

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
  br(4, '20-minute games', order: 3),
  br(5, 'Horror October', order: 4),
  br(31, 'With Sam', parent: 3, order: 0),
  br(32, 'Party', parent: 3, order: 1),
];
final placements = {
  1: [101, 102, 103, 104],
  2: [105, 106, 107],
  31: [108, 109],
  32: [110, 111, 112],
  4: [113, 101, 114],
  5: [115, 116],
};
final items = [
  game(101, 'Stardew Valley', progress: Progress.playing),
  game(102, 'Unpacking', progress: Progress.finished),
  game(103, 'A Short Hike'),
  game(104, 'Spiritfarer'),
  game(105, 'Outer Wilds', progress: Progress.finished),
  game(106, 'Disco Elysium'),
  game(107, 'Pentiment', own: Ownership.spotted),
  game(108, 'It Takes Two'),
  game(109, 'Deep Rock Galactic', progress: Progress.playing),
  game(110, 'Overcooked 2'),
  game(111, 'Jackbox 9'),
  game(112, 'Gang Beasts'),
  game(113, 'Hades', progress: Progress.playing),
  game(114, 'Balatro'),
  game(115, 'Inscryption'),
  game(116, 'Signalis'),
  game(117, 'Celeste'),
];

Future<void> loadRoboto() async {
  // flutter_tester lives under <sdk>/bin/cache/artifacts/engine/<platform>/;
  // walk up to the artifacts directory that holds material_fonts.
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
  const phone = Size(390, 700);

  Future<void> capture(WidgetTester tester, String name,
      {List<Branch>? bs, Map<int, List<int>>? pl, int? zoom, int unfiled = 0, bool none = false}) async {
    final key = GlobalKey();
    final view = GlobalKey<CanopyViewState>();
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
              child: CanopyView(
                key: view,
                items: none ? const [] : items,
                branches: bs ?? branches,
                placements: pl ?? placements,
                unfiledCount: unfiled,
                onSelect: (_) {},
                onCreateBranch: (_) {},
                onPick: (_, _) {},
                onSwitchView: () {},
                bottomInset: 72,
                rightInset: 64,
              ),
            ),
          ),
        ),
      ));
      if (zoom != null) {
        view.currentState!.zoomTo(zoom, BranchTree(bs ?? branches, pl ?? placements));
      }
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = io.Directory('../docs/shots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = io.File('${dir.path}/canopy-$name.png')
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.existsSync(), isTrue);
    });
  }

  testWidgets('root', (t) => capture(t, 'root', unfiled: 3));
  testWidgets('zoomed into a branch with sub-branches',
      (t) => capture(t, 'couch-coop', zoom: 3));
  testWidgets('leaf branch fans its games',
      (t) => capture(t, 'chill-nights', zoom: 1));
  testWidgets('games but no branches hang on the trunk',
      (t) => capture(t, 'trunk-only', bs: const [], pl: const {}, unfiled: 17));
  testWidgets('first run', (t) => capture(t, 'empty', bs: const [], pl: const {}, unfiled: 0, none: true));
  testWidgets('eight branches fold into +N', (t) => capture(t, 'overflow', bs: [
        for (var i = 1; i <= 8; i++) br(i, ['Chill', 'Story', 'Co-op', 'Short', 'Horror', 'Racing', 'Retro', 'Someday'][i - 1], order: i),
      ], pl: {
        for (var i = 1; i <= 8; i++) i: [100 + i],
      }));

  group('layout rules', () {
    final tree = BranchTree(branches, placements);

    for (final size in const [Size(360, 560), Size(390, 700), Size(430, 800)]) {
      for (final focus in const [null, 3, 1]) {
        test('$size focus=$focus stays in the box and chips do not collide', () {
          final l = CanopyLayout.build(tree, focus, size,
              topClear: 48, bottomClear: 170);
          final rects = l.chipRects();
          for (final r in rects) {
            expect(r.left >= 0 && r.right <= size.width, isTrue,
                reason: 'chip $r leaves the width');
            expect(r.top >= 48, isTrue, reason: 'chip $r under the top bar');
          }
          for (var i = 0; i < rects.length; i++) {
            for (var j = i + 1; j < rects.length; j++) {
              expect(rects[i].deflate(1).overlaps(rects[j].deflate(1)), isFalse,
                  reason: 'chips $i and $j overlap');
            }
          }
          // Labels need ~150 x 30; neighbours must not share that box.
          final labels = [for (final f in l.fans) f.label];
          for (var i = 0; i < labels.length; i++) {
            expect(labels[i].dx - 58 >= 0 && labels[i].dx + 58 <= size.width,
                isTrue, reason: 'label ${l.fans[i].branch.name} clipped');
            for (var j = i + 1; j < labels.length; j++) {
              final d = labels[i] - labels[j];
              expect(d.dx.abs() > 110 || d.dy.abs() > 30, isTrue,
                  reason: '${l.fans[i].branch.name} vs ${l.fans[j].branch.name}');
            }
          }
        });
      }
    }

    for (final size in const [Size(360, 560), Size(390, 700), Size(430, 800)]) {
      test('$size games on a bare trunk do not collide', () {
        final l = CanopyLayout.build(BranchTree(const []), null, size,
            topClear: 88, bottomClear: 170,
            trunkGames: [for (var i = 0; i < 17; i++) i]);
        final rects = l.chipRects();
        expect(rects.length + l.more, 17, reason: 'every game shown or counted');
        expect(l.moreAt != null, l.more > 0);
        if (size.height >= 700) {
          expect(l.more, 0, reason: 'a phone-sized trunk shows all 17');
        }
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].left >= 0 && rects[i].right <= size.width, isTrue);
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse,
                reason: 'trunk chips $i and $j overlap at $size');
          }
        }
      });
    }

    test('more than six branches fold, never draw a seventh label', () {
      final many = BranchTree(
          [for (var i = 1; i <= 9; i++) br(i, 'B$i', order: i)]);
      final l = CanopyLayout.build(many, null, const Size(390, 700));
      expect(l.fans, hasLength(kMaxFanned - 1));
      expect(l.more, 9 - (kMaxFanned - 1));
      expect(l.moreAt, isNotNull);
    });
  });
}
