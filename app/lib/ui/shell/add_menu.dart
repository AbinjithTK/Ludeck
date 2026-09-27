import 'package:flutter/material.dart';

import '../tokens.dart';

/// The ways a game can get onto the tree.
///
/// Ordered by how little work each one asks of the person. Pasting a link is
/// first because it is the one that happens while they are still looking at the
/// thing that made them want the game.
enum AddAction {
  pasteLink('Paste a link'),
  search('Search by name'),
  manual('Add by hand');

  const AddAction(this.label);
  final String label;
}

/// A plus anchored to the bottom left that expands into a short stack of pills.
///
/// Taken from `tolan/home/08-plus-action-menu.png`: the pills rise from the
/// button rather than arriving from off screen, and the plus itself rotates into
/// a close mark so the same target both opens and closes. One target, two
/// states, no second button to find.
///
/// There is no dimming scrim. The whole point of the Tolan layout is that the
/// scene stays visible while something happens on top of it, and a scrim would
/// throw that away for no gain: the pills already read as being in front.
class AddMenu extends StatefulWidget {
  const AddMenu({super.key, required this.onAction});

  final ValueChanged<AddAction> onAction;

  @override
  State<AddMenu> createState() => _AddMenuState();
}

class _AddMenuState extends State<AddMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Short, because this is a menu and not a transition. Anything slower makes
    // the second tap feel like it was ignored.
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 190),
  );

  bool get _open => _c.value > 0.5;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _c.reverse();
    } else {
      _c.forward();
    }
  }

  /// Each pill starts slightly after the one below it, so the stack reads as
  /// unfolding from the button instead of appearing all at once.
  ///
  /// The intervals overlap on purpose. A clean sequential stagger looks
  /// mechanical at this length; overlapping keeps it one gesture.
  Animation<double> _stagger(int index, int count) {
    final start = 0.12 * (count - 1 - index);
    return CurvedAnimation(
      parent: _c,
      curve: Interval(start, (start + 0.7).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0, 1, curve: Curves.easeIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    const actions = AddAction.values;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The pills are FLEXIBLE and scrollable; the button below is not.
        //
        // The pills grow with the user's text-size setting, and at 2x scale the
        // open menu is taller than the band it floats in -- a plain Column
        // overflowed by 51px. A floating menu has to survive its own content
        // getting bigger rather than assume it always fits. `reverse: true` keeps
        // the stack anchored to the button when it does have to scroll, so the
        // pill nearest your thumb is the one that stays put.
        Flexible(
          child: SingleChildScrollView(
            reverse: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < actions.length; i++)
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final t = _stagger(i, actions.length).value;
                      // Skipped entirely when closed, so a collapsed menu cannot
                      // eat taps meant for the tree behind it.
                      if (t == 0) return const SizedBox.shrink();
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - t)),
                          child: Padding(
                            padding: EdgeInsets.only(bottom: Tokens.space.xs),
                            child: _Pill(
                              label: actions[i].label,
                              onTap: () {
                                _c.reverse();
                                widget.onAction(actions[i]);
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),

        AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.rotate(
            // Forty five degrees turns the plus into a close mark. It is the
            // same glyph, so the button never has to swap its icon.
            angle: _c.value * 0.785398,
            child: child,
          ),
          child: Semantics(
            button: true,
            label: 'Add a game',
            child: Material(
              // Deliberately NOT the accent colour: gold means exactly one
              // thing, harvested (a design critique caught it doing two jobs).
              //
              // Glass rather than a solid white disc. A solid white disc was
              // the brightest object on the orchard and pulled the eye off the
              // tree. The plus glyph keeps full text contrast, the panel edge
              // gives the control its boundary, and the fill lets the sky
              // through like the navigation pill beside it.
              color: Tokens.cosmos.panel,
              shape: CircleBorder(
                  side: BorderSide(color: Tokens.cosmos.panelEdge)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggle,
                child: SizedBox(
                  width: Tokens.size.control,
                  height: Tokens.size.control,
                  child: Icon(Icons.add, color: Tokens.palette.text, size: 26),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Tokens.palette.surface,
        borderRadius: BorderRadius.circular(Tokens.radius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radius.pill),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Tokens.space.md, vertical: Tokens.space.sm),
            child: Text(
              label,
              style: TextStyle(
                fontSize: Tokens.type.body,
                color: Tokens.palette.text,
              ),
            ),
          ),
        ),
      );
}
