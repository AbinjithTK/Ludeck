// The tree's colour is a SKIN, chosen 2026-09-26 from real renders.
//
// These are not pixel assertions -- the colour was judged from the `skin-*`
// captures, which is the only honest way to judge colour. What is guarded here
// is the machinery and the fences, so a later edit cannot quietly ship a skin
// that breaks a rule or point the app at the wrong one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/ui/tokens.dart';

void main() {
  final all = [
    Tokens.skins.midnight,
    Tokens.skins.biolume,
    Tokens.skins.twilight,
    Tokens.skins.neon,
  ];

  test('the shipped skin is biolume, the direction chosen from renders', () {
    // A one-line revert changes this; the test is what makes the change
    // deliberate rather than accidental.
    expect(Tokens.activeSkin.name, 'biolume');
    // Tokens.canopy resolves through the active skin.
    expect(Tokens.canopy.name, Tokens.activeSkin.name);
  });

  test('every skin carries a full material, a sky and a glow', () {
    for (final s in all) {
      expect(s.name, isNotEmpty);
      expect(s.sky.length, greaterThanOrEqualTo(2),
          reason: '${s.name}: a gradient needs at least two stops');
      // Bark is three values so a stem reads as a cylinder, not a ribbon.
      expect({s.barkShade, s.barkMid, s.barkLit}.length, 3,
          reason: '${s.name}: the three bark values must differ');
      expect({s.foliageNear, s.foliageFar, s.foliageLit}.length, 3,
          reason: '${s.name}: the three foliage values must differ');
    }
  });

  test('a skin never reaches for a _Palette content colour', () {
    // The fence in DECISIONS.md: a skin colours bark and leaf, never text, a
    // status, a control or a count. gold (accent) in particular keeps its one
    // meaning, so no skin material may BE gold.
    final content = {
      Tokens.palette.bg,
      Tokens.palette.surface,
      Tokens.palette.text,
      Tokens.palette.textDim,
      Tokens.palette.accent,
      Tokens.palette.danger,
    };
    for (final s in all) {
      final materials = <Color>[
        s.barkShade, s.barkMid, s.barkLit,
        s.foliageNear, s.foliageFar, s.foliageLit,
        s.ground, s.groundLit, s.glow,
      ];
      for (final c in materials) {
        expect(content.contains(c), isFalse,
            reason: '${s.name}: a skin material collides with a _Palette '
                'content colour, which would give it a second meaning');
      }
    }
  });

  test('midnight is preserved unchanged as the fallback baseline', () {
    // The exact values that shipped before the skin change, so a revert is a
    // known-good state and not a guess.
    final m = Tokens.skins.midnight;
    expect(m.barkMid, const Color(0xFF3E2F3A));
    expect(m.foliageNear, const Color(0xFF2E5A4E));
    expect(m.sky, const [Color(0xFF0B0A1C), Color(0xFF16112E), Color(0xFF241A3D)]);
    // The old muted tree had no glow; that is what a lit skin adds.
    expect(m.glow.a, 0);
  });

  test('the shipped skin actually glows, which the muted one did not', () {
    // biolume/twilight/neon are "lit" -- the crown-glow pass keys off glow
    // alpha, so a shipped lit skin must carry it or the render is unchanged.
    expect(Tokens.activeSkin.glow.a, greaterThan(0));
  });
}
