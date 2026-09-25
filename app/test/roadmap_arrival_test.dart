// A game appearing on the map.
//
// The contract under test is not "does it animate" but "does it animate the
// RIGHT thing, once": the first build must animate nothing (opening the app is
// not eight games arriving), only a game added AFTER that animates, and the
// animateArrivals=false path a test uses for geometry must be inert.
//
// A pure widget test -- RoadmapView takes plain lists, no database.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/map/roadmap_view.dart';

TreeItem _item(int id, String title) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: Progress.untouched,
      ),
      copies: const [],
    );

/// A harness that lets the test change the item list under one RoadmapView, so
/// "a game appears" is a real state change on a mounted widget rather than two
/// separate pumps of two separate widgets (which would not exercise
/// didUpdateWidget, where the arrival is detected).
class _Harness extends StatefulWidget {
  const _Harness({required this.initial});
  final List<TreeItem> initial;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<TreeItem> _items = widget.initial;

  void setItems(List<TreeItem> items) => setState(() => _items = items);

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: RoadmapView(
            items: _items,
            topInset: 0,
            bottomInset: 0,
            onSelect: (_) {},
            onHold: (_) {},
          ),
        ),
      );
}

/// How far into its arrival a node is, read from the fade Opacity that wraps it.
/// 1.0 means settled; below 1 means the arrival spring is mid-flight.
///
/// The fade rather than the scale Transform: FittedBox and InkWell insert their
/// own Transforms into the node, so an ancestor-Transform finder is ambiguous,
/// but the only Opacity in a node's subtree is the arrival fade.
double _nodeOpacity(WidgetTester tester, String title) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(of: find.text(title), matching: find.byType(Opacity))
        .first,
  );
  return opacity.opacity;
}

void main() {
  testWidgets('the first build animates nothing', (tester) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_Harness(initial: [
      _item(1, 'Hades'),
      _item(2, 'Celeste'),
    ]));
    // One frame only -- no settle. If the first build animated, the nodes would
    // be mid-spring (scale < 1) right now.
    await tester.pump();

    expect(_nodeOpacity(tester, 'Hades'), 1.0,
        reason: 'opening the app is not every game arriving at once');
    expect(_nodeOpacity(tester, 'Celeste'), 1.0);
  });

  testWidgets('a game added after the first build animates in', (tester) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_Harness(initial: [_item(1, 'Hades')]));
    await tester.pump();

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.setItems([_item(1, 'Hades'), _item(2, 'Celeste')]);
    // First pump applies the setState and runs didUpdateWidget (which marks
    // Celeste arriving); the new node's post-frame callback that STARTS the
    // spring then fires on the following frame. So pump once to build, once more
    // to let the callback run, then a short slice -- well inside the 260ms grow,
    // so the node is caught mid-flight.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(_nodeOpacity(tester, 'Celeste'), lessThan(1.0),
        reason: 'the newly added game should be mid arrival');
    // And the game that was already there does NOT animate.
    expect(_nodeOpacity(tester, 'Hades'), 1.0,
        reason: 'an existing game must not re-animate when a sibling arrives');

    // It settles to full size.
    await tester.pumpAndSettle();
    expect(_nodeOpacity(tester, 'Celeste'), 1.0);
  });

  testWidgets('animateArrivals=false leaves nodes settled from frame one',
      (tester) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoadmapView(
          items: [_item(1, 'Hades')],
          animateArrivals: false,
          topInset: 0,
          bottomInset: 0,
          onSelect: (_) {},
          onHold: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(_nodeOpacity(tester, 'Hades'), 1.0);
  });
}
