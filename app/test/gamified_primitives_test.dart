// The gamified primitives.
//
// A pure widget test: no database, so no `tester.runAsync` and no check.ps1
// rule 8 concern. What is worth asserting here is NOT "it renders" -- it is the
// handful of contracts that would fail silently and look like a design problem:
// a NaN progress value throwing in the render phase, a starfield that repaints
// every frame, and a halo that swallows taps around an orb.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/gamified/gallery.dart';
import 'package:ludeck/ui/gamified/primitives.dart';
import 'package:ludeck/ui/tokens.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CosmosBackdrop(child: child))),
    );

void main() {
  group('PillProgress', () {
    // These four are the reason the widget clamps instead of asserting. The
    // value is computed from collection counts upstream, so an empty collection
    // divides by zero and a miscount can exceed 1 -- both would paint a
    // negative- or NaN-width box and throw during layout, which surfaces as a
    // red screen rather than as a wrong bar.

    testWidgets('a value over 1 does not throw or overflow', (tester) async {
      await _pump(tester, const PillProgress(value: 4.2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative value does not throw', (tester) async {
      await _pump(tester, const PillProgress(value: -1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('NaN does not throw', (tester) async {
      await _pump(tester, const PillProgress(value: double.nan));
      expect(tester.takeException(), isNull);
    });

    testWidgets('infinity does not throw', (tester) async {
      await _pump(tester, const PillProgress(value: double.infinity));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the filled portion tracks the value', (tester) async {
      await _pump(tester, const PillProgress(value: 0.5));

      final box = tester.widget<FractionallySizedBox>(
          find.byType(FractionallySizedBox));
      expect(box.widthFactor, 0.5);
    });

    testWidgets('a clamped value reaches the bar clamped, not raw',
        (tester) async {
      await _pump(tester, const PillProgress(value: 4.2));

      final box = tester.widget<FractionallySizedBox>(
          find.byType(FractionallySizedBox));
      expect(box.widthFactor, 1.0,
          reason: 'a widthFactor above 1 lays the fill outside its own track');
    });

    testWidgets('the label renders in the leading cap when given',
        (tester) async {
      await _pump(tester, const PillProgress(value: 0.3, label: '7'));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('no label means no cap, not an empty one', (tester) async {
      await _pump(tester, const PillProgress(value: 0.3));
      // Scoped: the labelled form is the only one that wraps the bar in a Row,
      // and an unscoped Row finder would catch anything an ancestor built.
      expect(
        find.descendant(
            of: find.byType(PillProgress), matching: find.byType(Row)),
        findsNothing,
      );
    });
  });

  group('CosmosBackdrop', () {
    testWidgets('the starfield does not repaint when nothing changed',
        (tester) async {
      // A field that repaints every frame would shimmer, because a rebuild
      // happens on every scroll frame. The painter is a pure function of count
      // and size, so shouldReplaint must be false for an identical config.
      await _pump(tester, const SizedBox.shrink());

      final painter = tester
          .widget<CustomPaint>(find.descendant(
            of: find.byType(CosmosBackdrop),
            matching: find.byType(CustomPaint),
          ).first)
          .painter!;

      expect(painter.shouldRepaint(painter), isFalse);
    });

    testWidgets('stars: 0 paints no field at all', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CosmosBackdrop(stars: 0, child: SizedBox.shrink()),
      ));

      // CosmosBackdrop builds exactly one CustomPaint of its own, directly under
      // its DecoratedBox, and passes a null painter when there are no stars.
      // Asserting on that painter is the honest check; counting CustomPaint
      // widgets would count Flutter's internal ones too.
      final ours = tester.widget<CustomPaint>(find
          .descendant(
            of: find.byType(CosmosBackdrop),
            matching: find.byType(CustomPaint),
          )
          .first);

      expect(ours.painter, isNull);
    });

    testWidgets('the two skies use different gradients', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: CosmosBackdrop(sky: Sky.hero, child: SizedBox.shrink())));
      final hero = tester
          .widget<DecoratedBox>(find
              .descendant(
                  of: find.byType(CosmosBackdrop),
                  matching: find.byType(DecoratedBox))
              .first)
          .decoration as BoxDecoration;

      expect((hero.gradient! as LinearGradient).colors,
          Tokens.cosmos.hero,
          reason: 'the hero sky must not silently render the map sky');
    });
  });

  group('GlowOrb', () {
    // Scoped to the orb's own subtree: Scaffold and friends build their own
    // IgnorePointers, so an unscoped finder counts Flutter's as well as ours and
    // the assertion means nothing.
    Finder haloOf(Finder orb) => find.descendant(
          of: orb,
          matching: find.byType(IgnorePointer),
        );

    testWidgets('the halo does not swallow taps around the sphere',
        (tester) async {
      // The widget is deliberately larger than its sphere so the glow has room
      // to bloom. Without IgnorePointer on the halo, that padding would eat
      // taps meant for whatever sits beside the orb.
      await _pump(tester, GlowOrb(diameter: 40));
      expect(haloOf(find.byType(GlowOrb)), findsOneWidget);
    });

    testWidgets('glow 0 draws the sphere and no halo', (tester) async {
      await _pump(tester, GlowOrb(diameter: 40, glow: 0));
      expect(haloOf(find.byType(GlowOrb)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a child renders over the sphere', (tester) async {
      await _pump(tester, GlowOrb(diameter: 60, child: const Text('A')));
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('SoftCard', () {
    testWidgets('a static card builds no InkWell', (tester) async {
      // A static block of copy showing a ripple on touch reads as a broken
      // button, so the tappable form has to be opt-in rather than always built.
      await _pump(tester, const SoftCard(child: Text('static')));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a tappable card fires onTap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SoftCard(onTap: () => taps++, child: const Text('tap me')),
      );

      await tester.tap(find.text('tap me'));
      expect(taps, 1);
    });
  });

  group('StatChip', () {
    testWidgets('announces one sentence, not three fragments', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StatChip(
            icon: Icons.check_circle, value: '3', label: 'harvested'),
      );

      expect(find.bySemanticsLabel('3 harvested'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the gallery renders both skies', () {
    // The gallery is the thing a human looks at to judge the design, so it
    // failing to build would silently remove the only review surface.
    testWidgets('deep sky', (tester) async {
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: PrimitivesGallery()));
      expect(tester.takeException(), isNull);
      expect(find.text('GLOWORB'), findsOneWidget);
    });

    testWidgets('hero sky', (tester) async {
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(const MaterialApp(home: PrimitivesGallery(sky: Sky.hero)));
      expect(tester.takeException(), isNull);
    });
  });

  group('a tappable orb is tappable across its whole sphere', () {
    // This shipped broken and a missed tap on a device is what found it, which is
    // the wrong way round. `Container.alignment` wraps the child in an Align and
    // hands it LOOSE constraints, so the InkWell collapsed onto the glyph it
    // contained -- a level digit, about 20x28 -- while the sphere it appeared to
    // fill was 62. Measuring the hit region is the only way this stays fixed.
    const diameter = 62.0;

    testWidgets('the ink response fills the sphere, not just its glyph',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlowOrb(
              diameter: diameter,
              onTap: () {},
              child: const Text('2'),
            ),
          ),
        ),
      ));

      final ink = tester.getSize(find.byType(InkWell));

      // The border is drawn INSIDE the box, so the child is inset by its width
      // on each side. Asserting `== diameter` was wrong by exactly that, which
      // is why this asserts the requirement instead of a number: the hit region
      // is the sphere less its border, and comfortably past the 44pt minimum
      // touch target.
      expect(ink.width, greaterThanOrEqualTo(diameter - 2));
      expect(ink.height, greaterThanOrEqualTo(diameter - 2));
      expect(ink.shortestSide, greaterThanOrEqualTo(44));

      // And far larger than the glyph it contains, which is what it had collapsed
      // onto.
      final glyph = tester.getSize(find.text('2'));
      expect(ink.width, greaterThan(glyph.width * 2));
    });

    testWidgets('a tap near the sphere edge registers', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlowOrb(
              diameter: diameter,
              onTap: () => taps++,
              child: const Text('2'),
            ),
          ),
        ),
      ));

      // Inside the sphere but well outside the glyph -- the exact region the
      // broken version ignored.
      final centre = tester.getCenter(find.byType(InkWell));
      await tester.tapAt(centre + const Offset(diameter / 2 - 4, 0));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('an orb with no onTap builds no InkWell', (tester) async {
      // Map nodes and decorative planets must not show a stray ripple.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlowOrb(diameter: diameter, child: const Text('2')),
          ),
        ),
      ));

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
