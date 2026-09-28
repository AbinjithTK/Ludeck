// The sheet a game opens: where it stands, and where it hangs.
//
// It replaced a column of radio-dot list rows (2026-09-28) that read as a
// settings page: eleven rows of equal weight, each with the same grey
// subtitle ("Hang it here" four times), a gold dot for "selected" when gold
// means harvested everywhere else, and a surface grey that belonged to no
// part of the night scene it slid over.
//
// Now, top to bottom by priority:
//   1. the game itself: its cover and title, and one line saying where it is;
//   2. three questions, each answered by a row of choices you can see all of
//      at once, the current one filled white;
//   3. the tree choices carry each tree's own blossom colour, so the list
//      is recognisably the trees on the meadow and not a list of names;
//   4. rating, only for a harvested game.
//
// Still two independent axes, visibly separate (enums.dart): progress and
// ownership are different questions, so they are different rows.
//
// Presentational: every change is a callback, so a test can mount it with no
// store. main.dart wires it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../tokens.dart';
import 'fruit_look.dart';
import 'ground_tray.dart' show FruitImage;

/// One tree the game can hang on.
typedef SheetTree = ({int id, String name, Color swatch});

class GameSheet extends StatelessWidget {
  const GameSheet({
    super.key,
    required this.item,
    required this.trees,
    required this.currentTree,
    required this.onProgress,
    required this.onOwnership,
    required this.onTree,
    this.onRate,
    this.onRemove,
    this.onClose,
  });

  final TreeItem item;

  /// The trees, in the meadow's order. Empty hides the "Which tree" row: an
  /// offer to hang a game with nothing to hang it on is a dead control.
  final List<SheetTree> trees;

  /// The tree the game hangs on, or null when it is on the ground.
  final int? currentTree;

  final ValueChanged<Progress> onProgress;
  final ValueChanged<Ownership> onOwnership;
  final ValueChanged<int?> onTree;

  /// Opens the rating sheet. Only offered for a harvested game.
  final VoidCallback? onRate;

  /// Removes the game from Ludeck entirely (the honest hard delete). The
  /// caller confirms first and destroys the record; null hides the action.
  final VoidCallback? onRemove;

  /// Closes the sheet. Choices apply in place and no longer dismiss it, so
  /// the close button is the plain way out (a swipe down or a tap on the
  /// scrim still works too).
  final VoidCallback? onClose;

  String get _where {
    final t = trees.where((t) => t.id == currentTree).firstOrNull;
    return t == null ? 'On the ground' : 'On ${t.name}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Tokens.palette;
    final e = item.entry;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Tokens.cosmos.hillTop,
        shape: RoundedSuperellipseBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Tokens.radius.sheet))),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              Tokens.space.lg, Tokens.space.sm, Tokens.space.lg, Tokens.space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                      color: p.textDim.withValues(alpha: 0.4),
                      shape: const StadiumBorder()),
                ),
              ),
              SizedBox(height: Tokens.space.md),
              // 1. The game.
              Row(children: [
                ExcludeSemantics(
                  child: FruitImage(
                      game: item.game, look: lookOf(item), width: 52, radius: 8),
                ),
                SizedBox(width: Tokens.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: Tokens.type.displayFamily,
                              fontSize: Tokens.type.title,
                              fontWeight: FontWeight.w700,
                              letterSpacing: Tokens.type.trackingTitle,
                              height: 1.15,
                              color: p.text)),
                      SizedBox(height: Tokens.space.xxs),
                      Text('${e.progress.label}  ·  $_where',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Tokens.type.caption, color: p.textDim)),
                    ],
                  ),
                ),
                if (onClose != null) ...[
                  SizedBox(width: Tokens.space.xs),
                  _CloseButton(onTap: onClose!),
                ],
              ]),
              _Section(
                title: 'How far did you get',
                children: [
                  for (final v in Progress.values)
                    _Choice(
                      label: v.label,
                      selected: v == e.progress,
                      onTap: () => onProgress(v),
                    ),
                ],
              ),
              _Section(
                title: 'Do you have it',
                children: [
                  for (final v in Ownership.values)
                    _Choice(
                      label: v.label,
                      selected: v == e.ownership,
                      onTap: () => onOwnership(v),
                    ),
                ],
              ),
              if (trees.isNotEmpty)
                _Section(
                  title: 'Which tree',
                  children: [
                    _Choice(
                      label: 'On the ground',
                      hint: 'Not on a tree yet',
                      icon: Icons.grass_rounded,
                      selected: currentTree == null,
                      onTap: () => onTree(null),
                    ),
                    for (final t in trees)
                      _Choice(
                        label: t.name,
                        hint: 'Tree',
                        swatch: t.swatch,
                        selected: currentTree == t.id,
                        onTap: () => onTree(t.id),
                      ),
                  ],
                ),
              // Only for a harvested game, and only when the user opens this
              // sheet: a skipped rating stays reachable without becoming a nag.
              if (item.isHarvested && onRate != null)
                _Section(
                  title: 'What did you think',
                  children: [
                    _Choice(
                      label: e.rating == null
                          ? 'Rate it'
                          : 'Rated ${e.rating} out of 5',
                      icon: e.rating == null
                          ? Icons.star_border_rounded
                          : Icons.star_rounded,
                      selected: false,
                      onTap: onRate!,
                    ),
                  ],
                ),
              // Removing the game entirely: the honest hard delete, apart from
              // every other choice because it is not a status and it cannot be
              // undone. Quiet, at the very bottom, so it is reachable but never
              // the obvious thing to press.
              if (onRemove != null) _RemoveRow(onRemove: onRemove!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: Tokens.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title,
                  style: TextStyle(
                      fontSize: Tokens.type.caption,
                      fontWeight: FontWeight.w600,
                      color: Tokens.palette.textDim)),
            ),
            SizedBox(height: Tokens.space.xs),
            Wrap(
                spacing: Tokens.space.xs,
                runSpacing: Tokens.space.xs,
                children: children),
          ],
        ),
      );
}

/// One answer: a capsule, filled white when it is the current one. White,
/// not gold: gold means finished, and a selected "Want it" is not a finish.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hint,
    this.icon,
    this.swatch,
  });

  final String label;

  /// The plain-language word, for a screen reader (enums.dart: `label`).
  final String? hint;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// A tree's blossom colour, drawn as a dot before the name.
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final p = Tokens.palette;
    final fg = selected ? p.bg : p.text;
    return Semantics(
      button: true,
      selected: selected,
      label: hint == null || hint == label ? label : '$label, $hint',
      excludeSemantics: true,
      // The InkWell's own tap is excluded with its text, so the action is
      // restated here or a screen reader finds a label it cannot activate.
      onTap: onTap,
      child: Material(
        color: selected ? p.text : p.text.withValues(alpha: 0.07),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            // 44pt tall: the minimum comfortable touch target.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Tokens.space.md),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (swatch != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
                  ),
                  SizedBox(width: Tokens.space.xs),
                ] else if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  SizedBox(width: Tokens.space.xxs + 2),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: Tokens.type.body,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}


/// The sheet's close button: a quiet round glyph at the header's end, the
/// same weight as an unselected choice so it never competes with the answers.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Tokens.palette;
    return Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const Key('game-sheet-close'),
        color: p.text.withValues(alpha: 0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          // 44pt: the minimum comfortable touch target, like every choice.
          child: SizedBox.square(
            dimension: 44,
            child: Icon(Icons.close_rounded, size: 22, color: p.textDim),
          ),
        ),
      ),
    );
  }
}

/// The remove action, kept apart and quiet.
///
/// It is NOT a `_Choice`: a filled capsule among the answers would read as
/// one more status, and this destroys the record rather than setting one.
/// It sits alone at the bottom as a low-key destructive row in the danger
/// tone, so it is reachable but never the first thing the eye lands on. The
/// caller shows the confirm dialog; this only asks.
class _RemoveRow extends StatelessWidget {
  const _RemoveRow({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final danger = Tokens.palette.danger;
    return Padding(
      padding: EdgeInsets.only(top: Tokens.space.lg),
      child: Semantics(
        button: true,
        label: 'Remove from Ludeck',
        excludeSemantics: true,
        onTap: onRemove,
        child: Material(
          key: const Key('game-sheet-remove'),
          color: danger.withValues(alpha: 0.08),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onRemove,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: danger),
                  SizedBox(width: Tokens.space.xxs + 2),
                  Text('Remove from Ludeck',
                      style: TextStyle(
                          fontSize: Tokens.type.body,
                          fontWeight: FontWeight.w600,
                          color: danger)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
