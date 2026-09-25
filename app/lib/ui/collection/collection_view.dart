import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
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
class CollectionView extends StatefulWidget {
  const CollectionView({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onHold,
    required this.topInset,
    required this.bottomInset,
    this.branches = const [],
    this.placements = const {},
    this.coverCache,
    this.onCoverFound,
  });

  final List<TreeItem> items;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;

  /// The user's own branches, in their order. Empty is the normal starting state.
  final List<Branch> branches;

  /// Which game ids hang on which branch id.
  final Map<int, List<int>> placements;

  /// Looks up cover art for a row that has none. Defaults to null, and the
  /// default is the safe one on purpose: a widget test that pumps this view
  /// must not reach the network, matching `TreeScreen.metadata`'s null default
  /// for the same reason. `LudeckApp` supplies the real cache.
  final CoverArtCache? coverCache;

  /// Called when [coverCache] resolves a cover for a game that had none.
  /// `LudeckApp` wires this to `LudeckStore.applyCoverUrl` so the result is
  /// persisted and the row repaints; a test that passes [coverCache] without
  /// this simply drops the result, which is fine for asserting the request
  /// itself fired.
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  /// Space to keep clear at the top and bottom for the floating chrome.
  ///
  /// Passed IN rather than measured here, deliberately. This widget cannot see
  /// what its parent stacks on top of it, and when it tried to guess it
  /// budgeted for a one-line header that was actually two lines. The owner of
  /// the chrome is the only thing that knows its height, so the owner supplies
  /// it, from `ChromeMetrics`.
  final double topInset;
  final double bottomInset;

  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  /// Section keys the user has collapsed. Empty means everything is open, which
  /// is the right default: a collection that opens closed hides its own content.
  ///
  /// View state, so it lives here rather than in the store. Collapsing a section
  /// is not a fact about the collection and has no business being persisted with
  /// it.
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final groups = _group();

    return ListView(
      key: const Key('collection-list'),
      padding: EdgeInsets.fromLTRB(Tokens.space.md, widget.topInset,
          Tokens.space.md, widget.bottomInset),
      children: [
        for (final group in groups) ...[
          _GroupHeading(
            label: group.label,
            count: group.items.length,
            collapsed: _collapsed.contains(group.key),
            onToggle: () => setState(() {
              if (!_collapsed.remove(group.key)) _collapsed.add(group.key);
            }),
          ),
          if (!_collapsed.contains(group.key))
            for (final item in group.items)
              _GameRow(
                item: item,
                onTap: () => widget.onSelect(item),
                onLongPress: () => widget.onHold(item),
                coverCache: widget.coverCache,
                onCoverFound: widget.onCoverFound,
              ),
          SizedBox(height: Tokens.space.md),
        ],
      ],
    );
  }

  /// Groups the collection by the user's branches when there are any, and by
  /// status when there are not.
  ///
  /// The fallback is not a shortcut. Nothing seeds a branch, so a new install has
  /// none, and grouping by branch then produces a single unnamed heap of the
  /// whole collection: strictly less information than the status grouping it
  /// replaced. Branches earn the sectioning once the user has made some.
  List<_Group> _group() =>
      widget.branches.isEmpty ? _byStatus() : _byBranch();

  List<_Group> _byBranch() {
    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final placed = <int>{};
    final groups = <_Group>[];

    for (final branch in widget.branches) {
      final ids = widget.placements[branch.id] ?? const <int>[];
      final items = <TreeItem>[];
      for (final id in ids) {
        final item = byId[id];
        // A placement can point at a game the collection does not carry -- a
        // shelved row, most likely. Skipping keeps the heading's count equal to
        // the rows beneath it.
        if (item == null) continue;
        items.add(item);
        placed.add(id);
      }
      // An empty branch is still shown. The user made it deliberately, and
      // hiding it would look like it had been deleted.
      groups.add(_Group('branch-${branch.id}', branch.name, items));
    }

    // Unplaced last, and only when there is something in it. This is a real
    // state with its own meaning, not an error: it is where a freshly shared
    // game lands before the user files it.
    final unplaced =
        widget.items.where((i) => !placed.contains(i.game.igdbId)).toList();
    if (unplaced.isNotEmpty) {
      groups.add(_Group('unplaced', 'Not on a branch', unplaced));
    }
    return groups;
  }

  List<_Group> _byStatus() {
    List<TreeItem> where(bool Function(TreeItem) test) =>
        widget.items.where(test).toList();

    // A seed is defined by ownership; every other bucket is a progress state
    // of an owned game. Order runs most-active to least, seeds last.
    final buckets = <_Group>[
      _Group('playing', 'In hand',
          where((i) => !i.isSeed && i.entry.progress == Progress.playing)),
      _Group('installed', 'Within reach',
          where((i) => !i.isSeed && i.entry.progress == Progress.installed)),
      _Group('untouched', 'Growing',
          where((i) => !i.isSeed && i.entry.progress == Progress.untouched)),
      _Group('finished', 'Harvested',
          where((i) => !i.isSeed && i.entry.progress == Progress.finished)),
      _Group('abandoned', 'Set aside',
          where((i) => !i.isSeed && i.entry.progress == Progress.abandoned)),
      _Group('buds', 'Buds', where((i) => i.isSeed)),
    ];

    return buckets.where((g) => g.items.isNotEmpty).toList();
  }
}

class _Group {
  const _Group(this.key, this.label, this.items);

  /// Stable across rebuilds, so a collapsed section stays collapsed when the
  /// collection changes under it. A label would not do: renaming a branch would
  /// silently expand it.
  final String key;
  final String label;
  final List<TreeItem> items;
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // A heading AND a button, because it is both: it names the section and it
      // opens or closes it. `expanded` is what makes a screen reader announce
      // the state, which an icon alone communicates only to sighted users.
      header: true,
      button: true,
      expanded: !collapsed,
      label: count == 1 ? '$label, 1 game' : '$label, $count games',
      // The child's own text would otherwise be read again after the label.
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.only(
              top: Tokens.space.sm,
              bottom: Tokens.space.xs,
              left: Tokens.space.xxs),
          child: Row(
            children: [
              // Rotates rather than swapping glyphs, so the control reads as one
              // thing changing state instead of two different buttons.
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: Tokens.motion.swap,
                curve: Tokens.motion.easeOut,
                child: Icon(Icons.expand_more,
                    size: Tokens.type.caption + 4,
                    color: Tokens.palette.textDim),
              ),
              SizedBox(width: Tokens.space.xxs),
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
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.coverCache,
    this.onCoverFound,
  });

  final TreeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final game = item.game;
    final entry = item.entry;

    // Fired every build, but harmless: `CoverArtCache` itself is what remembers
    // an in-flight or finished lookup and refuses a second one, so a row that
    // rebuilds ten times while scrolling still asks the network at most once.
    // This does not need `initState` -- `_GameRow` is stateless on purpose,
    // since nothing it owns needs to survive a rebuild except what the cache
    // already tracks by igdbId.
    final cache = coverCache;
    if (cache != null && game.coverUrl == null) {
      cache.request(game.igdbId, game.title, (url) {
        onCoverFound?.call(game.igdbId, url);
      });
    }

    // The plain-language status label, never the metaphor word, so a screen
    // reader announces something a user actually understands. "Ripe" makes no
    // sense read aloud without the picture. Seeds report
    // who recommended them, since that is the seed's whole point.
    final statusLabel = item.isSeed
        ? 'Seed from ${entry.recommendedBy ?? 'somewhere'}'
        : entry.progress.label;

    final platforms = _orderedPlatforms(item.platforms);

    final meta = <String>[
      if (game.releaseYear != null) '${game.releaseYear}',
      if (game.hours != null) '${game.hours} h',
      for (final p in platforms) p.label,
    ].join('  \u00B7  ');

    // A rating belongs to a harvest, so it is shown and announced only on one.
    final showRating = item.isHarvested && (entry.rating ?? 0) > 0;

    // Everything the row conveys, as one sentence, in the order it matters.
    // Built from the plain labels rather than from the rendered widgets, because
    // the pips and the check mark carry meaning visually that has to be said out
    // loud to be carried at all.
    final announced = <String>[
      game.title,
      statusLabel,
      if (game.hours != null) 'about ${game.hours} hours',
      if (platforms.isNotEmpty)
        'on ${platforms.map((p) => p.label).join(', ')}',
      if (showRating) 'rated ${entry.rating} out of 5',
    ].join(', ');

    return Semantics(
      button: true,
      label: announced,
      // Without this the inner Text widgets are announced AGAIN after the label,
      // so the title and status are read twice and the metadata is read in a
      // form ("2017 . 26 h . PC") that does not make sense aloud.
      excludeSemantics: true,
      onLongPressHint: 'Change status',
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
                  _Cover(url: game.coverUrl),
                  SizedBox(width: Tokens.space.xxs),
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
                  _RatingOrStatus(item: item),
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

/// A small square thumbnail, or a placeholder tile when there is none yet.
///
/// Excluded from semantics entirely: the row's own `Semantics(label: announced)`
/// already speaks the title, and an image with no cover is decoration, not
/// content -- a screen reader gains nothing from being told a game has no
/// picture.
///
/// `Image.network` owns its own memory/disk cache (Flutter's default
/// `ImageCache`), so a URL that resolves once is not re-fetched on every
/// rebuild -- this widget adds no caching of its own on top of it.
class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String? url;

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Tokens.radius.card / 2);
    final placeholder = ClipRRect(
      borderRadius: radius,
      child: Container(
        width: _size,
        height: _size,
        color: Tokens.palette.bg,
        alignment: Alignment.center,
        child: Icon(Icons.videogame_asset_outlined,
            size: 18, color: Tokens.palette.textDim),
      ),
    );

    final src = url;
    if (src == null || src.isEmpty) {
      return Semantics(excludeSemantics: true, child: placeholder);
    }

    return Semantics(
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: radius,
        child: Image.network(
          src,
          key: ValueKey(src),
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          // A cover that fails to decode (a dead link, a network error) falls
          // back to the same placeholder rather than Flutter's default broken-
          // image icon, so a bad URL degrades to "no cover" instead of to a
          // visibly wrong one.
          errorBuilder: (context, error, stackTrace) => Container(
            width: _size,
            height: _size,
            color: Tokens.palette.bg,
            alignment: Alignment.center,
            child: Icon(Icons.videogame_asset_outlined,
                size: 18, color: Tokens.palette.textDim),
          ),
        ),
      ),
    );
  }
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

/// The right edge of a row: the status word, and a rating beneath it when the
/// game has been harvested and rated.
///
/// The rating used to REPLACE the status word, which made the column carry two
/// different kinds of information depending on the row: an unrated finished game
/// read "Finished" while a rated one read stars. Completion was still legible
/// from the check mark on the left, so nothing was lost, but nothing lines up
/// either. Status is now always present and the rating is additional.
///
/// It is shown only on a harvested game. A rating survives a game being moved
/// back out of finished -- deliberately, since it is a true record of a past
/// harvest and deleting it silently would be worse -- so without this check a
/// game that is merely "Playing" could display stars.
///
/// Pips render filled against outlined so they read without relying on colour.
class _RatingOrStatus extends StatelessWidget {
  const _RatingOrStatus({required this.item});

  final TreeItem item;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final rating = entry.rating ?? 0;
    final showRating = item.isHarvested && rating > 0;

    final status = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 84),
      child: Text(
        item.isSeed ? entry.ownership.label : entry.progress.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: Tokens.type.caption,
          color: Tokens.palette.textDim,
        ),
      ),
    );

    if (!showRating) return status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        status,
        SizedBox(height: Tokens.space.xxs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= rating ? Icons.star : Icons.star_border,
                size: 11,
                color: i <= rating
                    ? Tokens.palette.accent
                    : Tokens.palette.textDim,
              ),
          ],
        ),
      ],
    );
  }
}
