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

import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';
import 'roadmap_story_card.dart';

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
                  RoadmapStoryCard(games: widget.games, level: widget.level),
                  SizedBox(height: Tokens.space.md),
                  if (_hasLink)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The link itself, shown rather than merely copyable.
                        // "Copy link" alone asked the user to hand out a URL
                        // they had never seen, on the one screen whose whole
                        // subject is what leaves their device -- and a
                        // screen-reader user cannot inspect a clipboard to
                        // find out after the fact.
                        Semantics(
                          label: 'Your link, $_link',
                          excludeSemantics: true,
                          child: SoftCard(
                            deep: true,
                            child: Text(
                              _link,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: Tokens.type.caption,
                                color: Tokens.palette.textDim,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: Tokens.space.sm),
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
