// The share artifact: docs/FEATURES.md "A generated card carrying the tree, a
// sample game and light branding, with destinations beneath," plus copy-link and
// its toast (the toast must not dismiss the sheet).
//
// This screen renders AFTER a successful publish (or for a private save, after
// PublishBody's own confirmation -- see publish_screen.dart's `_published`
// branch, which routes here regardless of visibility so the flow always ends on
// one screen). It reads only the already-projected `PublishedGame` list, the
// same privacy-safe shape publish_screen.dart built.
//
// PRIVACY: nothing here reads `entry.recommendedBy`, `entry.note`, or a
// source's `channel`. `PublishedGame` carries no such field, so there is
// nothing to accidentally render.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/enums.dart';
import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';

/// The card plus its actions. Reachable whether or not the tree ended up
/// public -- a private save still confirms and still offers "copy link" is
/// hidden, since a private tree has no working link.
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({
    super.key,
    required this.games,
    required this.level,
    required this.handle,
  });

  final List<PublishedGame> games;
  final int level;

  /// Empty when the tree was saved private -- there is no live link to copy.
  final String handle;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  bool get _hasLink => widget.handle.isNotEmpty;

  String get _link => 'https://ludeck.app/t/${widget.handle}';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    // A toast, not a dialog -- FEATURES.md: "drops a toast in without dismissing
    // the sheet." A SnackBar over this Scaffold does exactly that; a dialog
    // would demand its own dismissal and read as an interruption for a copy
    // action that already succeeded.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Link copied'),
        backgroundColor: Tokens.cosmos.panelDeep,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.palette.bg,
        appBar: AppBar(
          backgroundColor: Tokens.palette.bg,
          foregroundColor: Tokens.palette.text,
          title: Text(
            _hasLink ? 'Your tree is live' : 'Saved privately',
            style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
          ),
        ),
        body: CosmosBackdrop(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(Tokens.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ShareCard(games: widget.games, level: widget.level),
                  SizedBox(height: Tokens.space.md),
                  if (_hasLink)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _copyLink,
                          icon: const Icon(Icons.link),
                          label: const Text('Copy link'),
                        ),
                        SizedBox(height: Tokens.space.sm),
                        // How a visitor's own "Plant" loop is reachable today,
                        // before search/deep-link intake exists: opening this
                        // exact link the way a friend would.
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  VisitScreen(handle: widget.handle),
                            ),
                          ),
                          child: const Text('See what a visitor sees'),
                        ),
                      ],
                    )
                  else
                    SoftCard(
                      deep: true,
                      child: Text(
                        "Only you can see this. Switch to Public any time to "
                        'get a link.',
                        style: TextStyle(
                            color: Tokens.palette.textDim,
                            fontSize: Tokens.type.caption),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// The generated card itself: tree summary, a sample game, light branding.
/// Fixed 4:5 aspect -- the same ratio ProfileBody's `_Portrait` uses, since
/// FEATURES.md calls this the same artifact as the profile avatar.
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.games, required this.level});

  final List<PublishedGame> games;
  final int level;

  @override
  Widget build(BuildContext context) {
    final harvested = games.where((g) => g.status == Progress.finished).length;
    // The sample game: the highest-rated harvested game, or just the first game
    // if nothing is rated yet. A card with zero games still renders -- an empty
    // tree is a real, nameable state, not an error.
    PublishedGame? sample;
    for (final g in games) {
      if (sample == null) {
        sample = g;
        continue;
      }
      if ((g.rating ?? -1) > (sample.rating ?? -1)) sample = g;
    }

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: SoftCard(
        deep: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                GlowOrb(diameter: 40, glow: 0.7, child: Text('$level')),
                SizedBox(width: Tokens.space.sm),
                Expanded(
                  child: Text(
                    'Level $level  ·  $harvested harvested',
                    style: TextStyle(
                      fontSize: Tokens.type.body,
                      fontWeight: FontWeight.w600,
                      color: Tokens.palette.text,
                    ),
                  ),
                ),
              ],
            ),
            if (sample != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.title,
                    style: TextStyle(
                      fontSize: Tokens.type.title,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.text,
                    ),
                  ),
                  if (sample.rating != null)
                    Text(
                      '${sample.rating}/5',
                      style: TextStyle(
                        fontSize: Tokens.type.caption,
                        color: Tokens.palette.textDim,
                      ),
                    ),
                ],
              )
            else
              Text(
                'Nothing harvested yet.',
                style: TextStyle(
                    fontSize: Tokens.type.body, color: Tokens.palette.textDim),
              ),
            Text(
              'Ludeck',
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.textDim,
                letterSpacing: Tokens.type.trackingTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
