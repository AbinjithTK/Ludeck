// Customise a tree: blossom colour, wood, and props on the ground around it.
//
// Every choice applies at once (saved and shown on the tree behind the sheet)
// and the sheet carries its own live preview, because the sheet covers the
// lower half of the screen where the tree's trunk and props stand. There is
// no Save button: a choice you can see and undo with one more tap does not
// need a confirmation step.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';
import '../tokens.dart';
import 'meadow.dart';
import 'rive_tree.dart';
import 'tree_style.dart';

Future<void> showTreeCustomiseSheet(
  BuildContext context, {
  required Branch tree,
  required TreeStyle initial,
  required void Function(TreeStyle style) onChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TreeCustomiseSheet(
          tree: tree, initial: initial, onChanged: onChanged),
    );

class TreeCustomiseSheet extends StatefulWidget {
  const TreeCustomiseSheet({
    super.key,
    required this.tree,
    required this.initial,
    required this.onChanged,
  });

  final Branch tree;
  final TreeStyle initial;
  final void Function(TreeStyle style) onChanged;

  @override
  State<TreeCustomiseSheet> createState() => _TreeCustomiseSheetState();
}

class _TreeCustomiseSheetState extends State<TreeCustomiseSheet> {
  late TreeStyle _style = widget.initial;

  void _set(TreeStyle next) {
    if (next == _style) return;
    HapticFeedback.selectionClick();
    setState(() => _style = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
        fontSize: Tokens.type.body,
        fontWeight: FontWeight.w600,
        color: Tokens.palette.text);
    final dim = TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.textDim);
    Widget heading(String title, String value) => Padding(
          padding: EdgeInsets.only(top: Tokens.space.lg, bottom: Tokens.space.sm),
          child: Row(children: [
            Text(title, style: label),
            SizedBox(width: Tokens.space.sm),
            Text(value, style: dim),
          ]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.lg, 0, Tokens.space.lg, Tokens.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(widget.tree.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.title,
                        fontWeight: FontWeight.w700,
                        color: Tokens.palette.text)),
              ),
              TextButton(
                key: const Key('customise-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ]),
            SizedBox(height: Tokens.space.sm),
            ExcludeSemantics(child: TreePreview(style: _style)),
            heading('Blossom', _style.blossom.label),
            _SwatchRow(
              keyPrefix: 'blossom',
              colours: [for (final b in TreeBlossom.values) b.swatch],
              labels: [for (final b in TreeBlossom.values) '${b.label} blossom'],
              selected: _style.blossom.index,
              onPick: (i) =>
                  _set(_style.copyWith(blossom: TreeBlossom.values[i])),
            ),
            heading('Wood', _style.wood.label),
            _SwatchRow(
              keyPrefix: 'wood',
              colours: [for (final w in TreeWood.values) w.swatch],
              labels: [for (final w in TreeWood.values) '${w.label} wood'],
              selected: _style.wood.index,
              onPick: (i) => _set(_style.copyWith(wood: TreeWood.values[i])),
            ),
            heading('Around the tree',
                _style.decor.isEmpty ? 'Nothing' : '${_style.decor.length} chosen'),
            Wrap(
              spacing: Tokens.space.sm,
              runSpacing: Tokens.space.sm,
              children: [
                for (final d in TreeDecor.values)
                  FilterChip(
                    key: Key('decor-${d.name}'),
                    avatar: Icon(d.icon, size: 18),
                    label: Text(d.label),
                    showCheckmark: false,
                    selected: _style.decor.contains(d),
                    onSelected: (on) => _set(_style.copyWith(
                        decor: on
                            ? {..._style.decor, d}
                            : ({..._style.decor}..remove(d)))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Circles for a one-of-N colour choice. Each is a 48pt target.
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.keyPrefix,
    required this.colours,
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  final String keyPrefix;
  final List<Color> colours;
  final List<String> labels;
  final int selected;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final dur = Tokens.motion.maybe(Tokens.motion.swap,
        reduceMotion: MediaQuery.disableAnimationsOf(context));
    return Wrap(
      spacing: Tokens.space.xs,
      children: [
        for (var i = 0; i < colours.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: labels[i],
            excludeSemantics: true,
            child: InkResponse(
              key: Key('$keyPrefix-$i'),
              onTap: () => onPick(i),
              radius: 26,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: dur,
                    curve: Tokens.motion.easeOut,
                    width: 38,
                    height: 38,
                    padding: EdgeInsets.all(i == selected ? 4 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: i == selected
                              ? Tokens.palette.text
                              : Tokens.cosmos.panelEdge,
                          width: i == selected ? 2 : 1),
                    ),
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: colours[i]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small meadow scene with one tree in [style]: what the orchard will show.
class TreePreview extends StatefulWidget {
  const TreePreview({super.key, required this.style, this.height = 220});
  final TreeStyle style;
  final double height;

  @override
  State<TreePreview> createState() => _TreePreviewState();
}

class _TreePreviewState extends State<TreePreview> {
  final ValueNotifier<double> _still = ValueNotifier(0);

  @override
  void dispose() {
    _still.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const soil = 26.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radius.card),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          final groundY = size.height - soil;
          final r = treeFrame(size, groundY, 1, headroom: 8);
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(
                painter: MeadowBackPainter(scroll: _still, groundFromBottom: soil)),
            // No halo here either: it banded into rings (see orchard_view).
            CustomPaint(
                painter: DecorPainter(
                    tree: r,
                    decor: widget.style.decor,
                    front: false,
                    groundY: groundY,
                    pageIndex: 0)),
            Positioned.fromRect(
              rect: r,
              child: RiveTree(
                games: const [],
                grownTarget: 9,
                fit: rv.Fit.contain,
                alignment: Alignment.center,
                asset: widget.style.asset,
              ),
            ),
            CustomPaint(
                painter: DecorPainter(
                    tree: r,
                    decor: widget.style.decor,
                    front: true,
                    groundY: groundY,
                    pageIndex: 0)),
            CustomPaint(
                painter:
                    MeadowFrontPainter(scroll: _still, groundFromBottom: soil)),
          ]);
        }),
      ),
    );
  }
}
