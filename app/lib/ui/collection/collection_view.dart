import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../tokens.dart';

/// A plain-Flutter view of the collection, standing in for the Rive tree while
/// the feature behaviour is built and tested.
///
/// This is deliberately NOT the tree. The tree is a visualisation problem that
/// wedges the Windows test runner (Rive's native library is absent there) and
/// hides feature behaviour behind a canvas nobody can read row by row. This
/// widget renders the exact same `List<TreeItem>` as ordinary Material list
/// rows, so every status, source and axis is visible and every callback the
/// screen wires up is exercised.
///
/// It honours the same contract as `TreeScene`:
///   - `onSelect` fires on a tap (the tree's tap-a-fruit).
///   - `onHold`   fires on a long-press (the tree's hold-a-fruit → status).
/// so `main.dart` swaps one widget for the other with no other change.
class CollectionView extends StatelessWidget {
  const CollectionView({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onHold,
  });

  final List<TreeItem> items;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;

  @override
  Widget build(BuildContext context) {
    // Grouped by the axis that actually matters to the user: on the tree,
    // growing, harvested, set aside, and seeds. Empty groups are omitted
    // rather than shown as a zero, matching the subline rule in main.dart.
    final groups = _group(items);

    // The header reserves the top ~150px in main.dart's Stack; the list must
    // start below it so the first row is not hidden under the headline.
    final topInset = MediaQuery.of(context).padding.top +
        Tokens.space.md +
        Tokens.type.display * Tokens.type.leadingDisplay +
        Tokens.space.lg;

    // And the AddMenu sits bottom-left, so the last row must clear it.
    final bottomInset = MediaQuery.of(context).padding.bottom + 96;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          Tokens.space.md, topInset, Tokens.space.md, bottomInset),
      children: [
        for (final group in groups) ...[
          _GroupHeading(label: group.label, count: group.items.length),
          for (final item in group.items)
            _GameRow(
              item: item,
              onTap: () => onSelect(item),
              onLongPress: () => onHold(item),
            ),
          SizedBox(height: Tokens.space.md),
        ],
      ],
    );
  }

  List<_Group> _group(List<TreeItem> items) {
    List<TreeItem> where(bool Function(TreeItem) test) =>
        items.where(test).toList();

    // A seed is defined by ownership; every other bucket is a progress state
    // of an owned game. Order runs most-active to least, seeds last.
    final buckets = <_Group>[
      _Group('In hand',
          where((i) => !i.isSeed && i.entry.progress == Progress.playing)),
      _Group('Within reach',
          where((i) => !i.isSeed && i.entry.progress == Progress.installed)),
      _Group('Growing',
          where((i) => !i.isSeed && i.entry.progress == Progress.untouched)),
      _Group('Harvested',
          where((i) => !i.isSeed && i.entry.progress == Progress.finished)),
      _Group('Set aside',
          where((i) => !i.isSeed && i.entry.progress == Progress.abandoned)),
      _Group('Seeds', where((i) => i.isSeed)),
    ];

    return buckets.where((g) => g.items.isNotEmpty).toList();
  }
}

class _Group {
  const _Group(this.label, this.items);
  final String label;
  final List<TreeItem> items;
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: Tokens.space.sm, bottom: Tokens.space.xs, left: Tokens.space.xxs),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: Tokens.type.caption,
              color: Tokens.palette.textDim,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(width: Tokens.space.xs),
          Text(
            '$count',
            style: TextStyle(
              fontSize: Tokens.type.caption,
              color: Tokens.palette.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final TreeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final game = item.game;
    final entry = item.entry;

    // The plain-language status label, never the metaphor word, so a screen
    // reader announces something a user actually understands. Seeds report
    // who recommended them, since that is the seed's whole point.
    final statusLabel = item.isSeed
        ? 'Seed from ${entry.recommendedBy ?? 'somewhere'}'
        : entry.progress.label;

    final meta = <String>[
      if (game.releaseYear != null) '${game.releaseYear}',
      if (game.hours != null) '${game.hours} h',
      for (final p in _orderedPlatforms(item.platforms)) p.label,
    ].join('  \u00B7  ');

    return Semantics(
      button: true,
      // Announced label uses plain words, never the tree metaphor.
      label: '${game.title}, $statusLabel',
      child: Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: Material(
          color: Tokens.palette.surface,
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radius.card),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: EdgeInsets.all(Tokens.space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _StatusMark(item: item),
                  SizedBox(width: Tokens.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Tokens.type.body,
                            color: Tokens.palette.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          SizedBox(height: Tokens.space.xxs),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Tokens.type.caption,
                              color: Tokens.palette.textDim,
                            ),
                          ),
                        ],
                        if (item.isSeed &&
                            entry.recommendedBy != null) ...[
                          SizedBox(height: Tokens.space.xxs),
                          Text(
                            'from ${entry.recommendedBy}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Tokens.type.caption,
                              color: Tokens.palette.textDim,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: Tokens.space.sm),
                  _RatingOrStatus(entry: entry, isSeed: item.isSeed),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Platforms in the enum's declared order (its layout order on the tree),
  /// so a game owned on two reads consistently.
  List<Platform> _orderedPlatforms(Set<Platform> set) =>
      Platform.values.where(set.contains).toList();
}

/// A small mark on the left of a row.
///
/// Harvested games carry a filled ring the same way the tree's harvested fruit
/// does — completion is readable by FORM (filled vs hollow), not by colour
/// alone, so it survives colour-blindness. This mirrors last session's fix on
/// the Rive fruit rather than reintroducing the colour-only bug in the list.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.item});

  final TreeItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isSeed) {
      // A hollow dim ring: present, but not on the tree yet.
      return Icon(Icons.circle_outlined,
          size: 18, color: Tokens.palette.textDim);
    }
    if (item.isHarvested) {
      // Filled: the one completion signal, readable by form.
      return Icon(Icons.check_circle, size: 18, color: Tokens.palette.text);
    }
    // Owned but not finished: a hollow bright ring.
    return Icon(Icons.circle_outlined, size: 18, color: Tokens.palette.text);
  }
}

/// The right edge of a row: a rating when one exists, otherwise the plain
/// status word. Rating renders as filled/hollow pips so it reads without
/// relying on colour.
class _RatingOrStatus extends StatelessWidget {
  const _RatingOrStatus({required this.entry, required this.isSeed});

  final Entry entry;
  final bool isSeed;

  @override
  Widget build(BuildContext context) {
    final rating = entry.rating;
    if (rating != null && rating > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star : Icons.star_border,
              size: 12,
              color: i <= rating
                  ? Tokens.palette.accent
                  : Tokens.palette.textDim,
            ),
        ],
      );
    }
    return Text(
      isSeed ? entry.ownership.label : entry.progress.label,
      style: TextStyle(
        fontSize: Tokens.type.caption,
        color: Tokens.palette.textDim,
      ),
    );
  }
}
