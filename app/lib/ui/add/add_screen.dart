// Search a catalogue and add a game. This is "save" in the Gaming criterion.
//
// The states here are the feature. A search box has five of them and collapsing
// any two is how a screen ends up lying:
//
//   idle       nothing typed yet, so nothing is claimed
//   searching  a request is in flight
//   results    matches, best first
//   empty      the query ran and matched nothing, which is NOT an error
//   failed     the query could not run, with a reason and a retry
//
// "No results" and "could not search" look the same to a careless implementation
// and mean opposite things to a person: one says the game is not there, the other
// says we do not know. Only the second is worth retrying.
//
// Debounced, because an un-debounced field fires a request per keystroke. On the
// fixture that is merely wasteful; against the proxy it is a rate limit and a
// bill.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../domain/title_match.dart';
import '../../services/catalog_service.dart';
import '../../services/http_catalog.dart';
import '../../state/ludeck_store.dart';
import '../common/loading_disc.dart';
import '../tokens.dart';

/// How long after the last keystroke the search actually runs.
///
/// 300ms is the usual sweet spot: long enough that typing a word is one request,
/// short enough that it does not feel like the field is ignoring you.
const Duration kSearchDebounce = Duration(milliseconds: 300);

class AddScreen extends StatefulWidget {
  const AddScreen({super.key, this.catalog, this.fileOnto});

  /// Injectable so a test can supply a fixture or a failing source. Defaults to
  /// whatever `resolveCatalog` decides, which is the fixture until the proxy
  /// exists.
  final CatalogSource? catalog;

  /// When set, a game added here is also filed onto this branch, not just left
  /// on the trunk. Used by the tree's "Add a game here" action so the add lands
  /// where the user asked for it.
  final int? fileOnto;

  @override
  State<AddScreen> createState() => _AddScreenState();
}

enum _Phase { idle, searching, results, empty, failed }

class _AddScreenState extends State<AddScreen> {
  late final CatalogSource _catalog = widget.catalog ?? resolveCatalog();
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  _Phase _phase = _Phase.idle;
  List<Game> _results = const [];
  CatalogFailure? _failure;

  /// Which query the in-flight request is for.
  ///
  /// Guards against an out-of-order response overwriting a newer one: type
  /// "hollow", then "hades", and the slower first request must not replace the
  /// second's results. Comparing the query is enough and needs no cancellation.
  String _inFlight = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();

    if (query.isEmpty) {
      // Back to idle rather than to an empty result. Nothing was asked, so
      // nothing can be said about what exists.
      setState(() {
        _phase = _Phase.idle;
        _results = const [];
        _failure = null;
      });
      return;
    }

    setState(() => _phase = _Phase.searching);
    _debounce = Timer(kSearchDebounce, () => _run(query));
  }

  Future<void> _run(String query) async {
    _inFlight = query;
    try {
      final games = await _catalog.search(query);
      if (!mounted || _inFlight != query) return;
      setState(() {
        _results = games;
        _phase = games.isEmpty ? _Phase.empty : _Phase.results;
        _failure = null;
      });
    } on CatalogException catch (e) {
      if (!mounted || _inFlight != query) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = e.failure;
        _results = const [];
      });
    } catch (_) {
      if (!mounted || _inFlight != query) return;
      // An unexpected error still has to land somewhere the user can see, rather
      // than as a silent empty list that says the game does not exist.
      setState(() {
        _phase = _Phase.failed;
        _failure = CatalogFailure.malformed;
        _results = const [];
      });
    }
  }

  /// Adds a game as a seed.
  ///
  /// Spotted, not owned: searching for a game is not buying it, and the two axes
  /// stay independent. The user changes ownership from the status sheet when they
  /// actually have it.
  ///
  /// The duplicate check matches on TITLE as well as id, and that is not
  /// belt-and-braces -- it is required. Two catalogue sources give the same game
  /// two different ids: the bundled asset derives a synthetic negative id from the
  /// title, while the live catalogue has the real one. Matching on id alone, the
  /// same game added from each source becomes two rows that look identical in the
  /// collection and cannot be told apart by the user.
  ///
  /// When a match exists the write is SKIPPED rather than performed. Upserting a
  /// different id would create the second row rather than update the first, so
  /// "already there" has to mean "do nothing" and not merely a different snackbar.
  Future<void> _add(Game game) async {
    final store = context.read<LudeckStore>();
    final key = catalogDedupKey(game.title);
    final already = (store.items ?? const []).any(
      (i) => i.game.igdbId == game.igdbId || catalogDedupKey(i.game.title) == key,
    );

    if (!already) {
      await store.upsert(TreeItem(
        game: game,
        entry: Entry(
          igdbId: game.igdbId,
          ownership: Ownership.spotted,
          progress: Progress.untouched,
        ),
        copies: const [],
      ));
    }
    // File it onto the branch the user opened this from, if any.
    if (widget.fileOnto != null) {
      await store.place(game.igdbId, widget.fileOnto!);
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Tokens.palette.surface,
      duration: const Duration(seconds: 2),
      content: Text(
        // Says which thing happened. "Added" on a game that was already there
        // would be a small lie, and the user would wonder why nothing changed.
        already
            ? '${game.title} is already in your collection.'
            : 'Added ${game.title}.',
        style: TextStyle(color: Tokens.palette.text),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tokens.palette.bg,
        title: Text('Add a game',
            style: Theme.of(context).textTheme.titleMedium),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: TextField(
              key: const Key('search-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: Tokens.palette.text),
              decoration: InputDecoration(
                hintText: 'Search by name',
                hintStyle: TextStyle(color: Tokens.palette.textDim),
                prefixIcon:
                    Icon(Icons.search, color: Tokens.palette.textDim),
              ),
              onChanged: _onChanged,
              // Enter searches NOW rather than waiting out the debounce. Someone
              // who pressed it has finished typing and said so.
              onSubmitted: (raw) {
                _debounce?.cancel();
                final query = raw.trim();
                if (query.isEmpty) return;
                setState(() => _phase = _Phase.searching);
                _run(query);
              },
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return _Message(
          key: const Key('state-idle'),
          title: 'Search for a game.',
          // Says what the source is. Until the proxy is deployed the catalogue is
          // a handful of fixture titles, and letting someone conclude their game
          // does not exist would be worse than saying so.
          body: catalogBaseUrl.isEmpty
              ? 'The full catalogue is not connected yet, so this searches a '
                  'small built-in list for now.'
              : 'Type a title. Results come from IGDB.',
        );

      case _Phase.searching:
        // Quiet for the first 350ms: a disc that appears for 80ms reads as a
        // flicker, and the bundled catalogue answers well inside that. Only a
        // real wait (the live catalogue, a slow network) earns the disc.
        return const DelayedSearchDisc();

      case _Phase.empty:
        return _Message(
          key: const Key('state-empty'),
          title: 'Nothing matched.',
          body: 'No game in the catalogue matches that. Check the spelling, or '
              'try fewer words.',
        );

      case _Phase.failed:
        return _Failed(
          failure: _failure ?? CatalogFailure.malformed,
          onRetry: () {
            final query = _controller.text.trim();
            if (query.isEmpty) return;
            setState(() => _phase = _Phase.searching);
            _run(query);
          },
        );

      case _Phase.results:
        return ListView.builder(
          key: const Key('search-results'),
          padding: EdgeInsets.symmetric(horizontal: Tokens.space.md),
          itemCount: _results.length,
          itemBuilder: (context, i) =>
              _ResultRow(game: _results[i], onAdd: () => _add(_results[i])),
        );
    }
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.game, required this.onAdd});

  final Game game;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (game.releaseYear != null) '${game.releaseYear}',
      if (game.hours != null) '${game.hours} h',
    ].join('  \u00B7  ');

    return Padding(
      padding: EdgeInsets.only(bottom: Tokens.space.xs),
      child: Semantics(
        button: true,
        label: <String>[
          game.title,
          if (game.releaseYear != null) '${game.releaseYear}',
          if (game.hours != null) 'about ${game.hours} hours',
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: Tokens.palette.surface,
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radius.card),
            onTap: onAdd,
            child: Padding(
              padding: EdgeInsets.all(Tokens.space.sm),
              child: Row(
                children: [
                  DiscCover(
                    url: game.coverUrl,
                    width: 40,
                    height: 40 * Tokens.size.coverRatio,
                    placeholder: _NoCover(
                        width: 40, height: 40 * Tokens.size.coverRatio),
                  ),
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
                          Text(meta,
                              style: TextStyle(
                                  fontSize: Tokens.type.caption,
                                  color: Tokens.palette.textDim)),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.add, size: 20, color: Tokens.palette.textDim),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The slot a cover would fill, for a result with no art. Flat on purpose: a
/// disc here would promise an image that is not coming.
class _NoCover extends StatelessWidget {
  const _NoCover({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Tokens.cosmos.panelDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Tokens.cosmos.panelEdge),
        ),
        child: Icon(Icons.videogame_asset_outlined,
            size: 18, color: Tokens.palette.textDim),
      );
}

/// A failure, named and retryable where retrying could help.
class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final CatalogFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Each one says something different, because they ARE different. Only the
    // first is the user's to act on.
    final (String title, String body, bool retryable) = switch (failure) {
      CatalogFailure.offline => (
          'No connection.',
          'The catalogue could not be reached. Nothing was changed.',
          true,
        ),
      CatalogFailure.rejected => (
          'The catalogue refused that.',
          'The search did not go through. Nothing was changed.',
          true,
        ),
      CatalogFailure.malformed => (
          'That answer could not be read.',
          'The catalogue replied with something unexpected. This is not '
              'something you can fix, and nothing was changed.',
          false,
        ),
      CatalogFailure.notConfigured => (
          'The catalogue is not connected.',
          'Searching the full catalogue needs a connection that is not set up '
              'yet.',
          false,
        ),
    };

    return _Message(
      key: const Key('state-failed'),
      title: title,
      body: body,
      action: retryable
          ? TextButton(
              onPressed: onRetry,
              child: Text('Try again',
                  style: TextStyle(color: Tokens.palette.accent)),
            )
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(Tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: Tokens.space.sm),
          Text(body,
              style: TextStyle(
                  fontSize: Tokens.type.body, color: Tokens.palette.text)),
          if (action != null) ...[
            SizedBox(height: Tokens.space.md),
            action!,
          ],
        ],
      ),
    );
  }
}
