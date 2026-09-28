import 'package:flutter/material.dart';

import '../common/glass.dart';
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
  void initState() {
    super.initState();
    // The overlay exists only while the menu is open or animating, so a
    // closed menu adds nothing above the scene.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed) {
        if (_portal.isShowing) _portal.hide();
      } else if (!_portal.isShowing) {
        _portal.show();
      }
    });
  }

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
    // The button alone takes layout space; the pills rise above it in the
    // overlay, anchored to it. So the button can sit INSIDE another control
    // (the orchard's ground tray) and the open menu never resizes that
    // control or gets clipped by it.
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: Offset(0, -Tokens.space.xs),
          child: Align(
            alignment: Alignment.bottomRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: _pills(),
            ),
          ),
        ),
        child: _button(),
      ),
    );
  }

  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  Widget _pills() {
    const actions = AddAction.values;
    return SingleChildScrollView(
            reverse: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
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
          );
  }

  Widget _button() {
    return AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.rotate(
            // Forty five degrees turns the plus into a close mark. It is the
            // same glyph, so the button never has to swap its icon.
            angle: _c.value * 0.785398,
            child: child,
          ),
          child: GlassButton(
              // Deliberately NOT the accent colour: gold means exactly one
              // thing, harvested. Glass like every control on the orchard,
              // so the brightest thing on screen stays the tree.
              label: 'Add a game',
              size: Tokens.size.control,
              onTap: _toggle,
              child: Icon(Icons.add_rounded, color: Tokens.palette.text, size: 28),
          ),
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
