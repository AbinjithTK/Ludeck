// Every gamified primitive on one screen, in both skies.
//
// This exists to be LOOKED AT. A primitive judged only by its test is judged on
// whether it renders, not on whether it looks right, and "does the glow read as
// depth or as a grey smudge" is not a question a test can answer.
//
// It is a real reachable screen rather than a temporary hack in `main.dart`,
// because a temporary hack is how the app ships pointing at a gallery. Nothing
// links to it in the shipped UI; it is opened deliberately, and it holds no state
// and touches no database, so it is safe to leave in the tree.

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'primitives.dart';

class PrimitivesGallery extends StatelessWidget {
  const PrimitivesGallery({super.key, this.sky = Sky.deep});

  final Sky sky;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CosmosBackdrop(
        sky: sky,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(Tokens.space.md),
            children: [
              _label('GlowOrb'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GlowOrb(
                    diameter: Tokens.size.orb * 0.5,
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.display,
                        color: Tokens.palette.text,
                      ),
                    ),
                  ),
                  // glow: 0 proves the halo is separable from the sphere -- a node
                  // that is merely present should not bloom like an avatar.
                  GlowOrb(diameter: Tokens.size.nodeCard * 0.6, glow: 0),
                  GlowOrb(diameter: Tokens.size.nodeCard * 0.6, glow: 0.5),
                ],
              ),

              _label('SoftCard'),
              SoftCard(
                child: Text(
                  'A translucent panel. The sky shows through it, which is what '
                  'makes it read as glass rather than as a rectangle.',
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    color: Tokens.palette.text,
                  ),
                ),
              ),
              SizedBox(height: Tokens.space.sm),
              SoftCard(
                deep: true,
                onTap: () {},
                child: Text(
                  'The deep fill, and tappable. Caption-sized text needs this '
                  'one over a bright gradient.',
                  style: TextStyle(
                    fontSize: Tokens.type.caption,
                    color: Tokens.palette.textDim,
                  ),
                ),
              ),

              _label('PillProgress'),
              const PillProgress(value: 0.0),
              SizedBox(height: Tokens.space.sm),
              const PillProgress(value: 0.35, label: '1'),
              SizedBox(height: Tokens.space.sm),
              const PillProgress(value: 1.0, label: '12'),
              SizedBox(height: Tokens.space.sm),
              // Out of range and non-finite, on screen, because both are
              // reachable from a count-derived value on an empty collection.
              const PillProgress(value: 4.2, label: 'hi'),
              SizedBox(height: Tokens.space.sm),
              const PillProgress(value: double.nan),

              _label('StatChip'),
              // Horizontally scrolling, not a plain Row. Three chips overflow a
              // 412pt phone by 74px, which the gallery caught -- and scrolling is
              // also what the Tolan reference does: its bottom row runs off the
              // screen edge rather than squeezing its cards.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const StatChip(
                        icon: Icons.check_circle,
                        value: '3',
                        label: 'harvested'),
                    SizedBox(width: Tokens.space.sm),
                    const StatChip(
                        icon: Icons.circle_outlined, value: '2', label: 'seeds'),
                    SizedBox(width: Tokens.space.sm),
                    const StatChip(
                        icon: Icons.account_tree_outlined,
                        value: '4',
                        label: 'branches'),
                  ],
                ),
              ),

              SizedBox(height: Tokens.space.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: EdgeInsets.only(top: Tokens.space.lg, bottom: Tokens.space.xs),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: Tokens.type.caption,
            color: Tokens.palette.textDim,
            letterSpacing: 1.5,
          ),
        ),
      );
}
