// Sharing, in one sheet.
//
// It replaced a three-screen flow (2026-09-28): profile row -> a consent
// screen with a Private/Public segmented control and "Save and share", which
// signed you in and published before you had seen anything -> a confirmation
// screen with the card, a Share button, the link in a box and Copy link. To
// send a picture of your orchard to a friend took three screens, an account
// and a publish.
//
// Now the card is the first thing you see, and the two ways to share are
// separate because they are different acts:
//
//   Share image   the card through the phone's own share sheet. Nothing is
//                 published and no account is needed: the image goes only
//                 where you send it. The primary action.
//   Public link   a switch, OFF by default (FEATURES.md: default private).
//                 Its consequence is written beside it before you touch it.
//                 Turning it on signs in if needed and publishes; then the
//                 link is shown and one tap copies it. Turning it off makes
//                 the tree private again.
//
// DECISIONS.md: "Never gate sharing." No entitlement check anywhere here.
// PRIVACY: renders and publishes only `PublishedGame` (see publish_export),
// which has no field for a note, a recommender or a source.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/level.dart';
import '../../domain/season.dart';
import '../../services/share_out.dart';
import '../../services/social/social_backend.dart';
import '../../services/social/tree_links.dart';
import '../../state/ludeck_store.dart';
import '../orchard/orchard_view.dart' show treesOf;
import '../orchard/tree_style.dart';
import '../tokens.dart';
import 'orchard_story_card.dart';
import 'publish_screen.dart'
    show toPublishedForBranch, toPublishedOffBranch, trunkGroupName;

/// Open the share sheet for the store's collection.
Future<void> showShareSheet(BuildContext context) {
  final store = context.read<LudeckStore>();
  final backend = context.read<SocialBackend>();
  final items = store.items ?? const <TreeItem>[];
  final games = <PublishedGame>[
    for (final b in store.branches) ...toPublishedForBranch(items, store, b),
    ...toPublishedOffBranch(items, store),
  ];
  final level = levelFor(summarise(items).harvested).level;
  // The owner's own tree colours, by name, so the card is the orchard they
  // see at home and not a default palette.
  final trees = treesOf(store.branches);
  final resolved = resolveTreeStyles(trees.map((b) => b.id).toList(), store.treeStyles);
  final styles = <String, TreeStyle>{
    for (final (i, t) in trees.indexed)
      t.name: resolved[t.id] ?? TreeStyle.defaultFor(i),
  };
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.palette.bg.withValues(alpha: 0),
    builder: (_) => ShareSheet(
        backend: backend, games: games, level: level, styles: styles),
  );
}

/// The sheet itself, injectable for tests: no store, a fake backend.
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.backend,
    required this.games,
    required this.level,
    this.styles = const {},
  });

  final SocialBackend backend;
  final List<PublishedGame> games;
  final int level;
  final Map<String, TreeStyle> styles;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final GlobalKey _card = GlobalKey();
  bool _sharing = false;
  bool _working = false;
  String? _error;

  /// The live public link, or null while the tree is private.
  String? _handle;

  String get _link => treeLinkFor(_handle!);

  Future<Uint8List?> _cardPng() async {
    try {
      final box = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null) return null;
      final img = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    final png = await _cardPng();
    final text = _handle != null
        ? 'My game orchard on Ludeck: $_link'
        : 'My game orchard, grown on Ludeck';
    final ok = await ShareOut.share(text: text, png: png);
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) {
      setState(() => _error = _handle != null
          ? "This device can't share images yet. Copy the link instead."
          : "This device can't share images yet.");
    }
  }

  Future<void> _setPublic(bool public) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (widget.backend.currentProfile == null) await widget.backend.signIn();
      await widget.backend.publish(
          games: widget.games, level: widget.level, isPublic: public);
      if (!mounted) return;
      setState(() {
        _working = false;
        _handle = public ? widget.backend.currentProfile?.handle : null;
        if (_handle != null && _handle!.isEmpty) _handle = null;
      });
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = switch (e.failure) {
          SocialFailure.notConfigured =>
            "Links aren't set up on this build yet. Nothing left this device.",
          SocialFailure.offline => "Couldn't reach the network. Nothing was shared.",
          SocialFailure.unauthorized => "Sign-in didn't complete. Nothing was shared.",
          _ => 'Something went wrong on our side. Nothing was shared.',
        };
      });
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link));
    HapticFeedback.selectionClick();
    // Said in place: a snackbar would sit under this sheet, out of sight.
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final public = _handle != null;
    final t = Tokens.palette;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Tokens.cosmos.hillTop,
        shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radius.sheet))),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              Tokens.space.lg, Tokens.space.sm, Tokens.space.lg, Tokens.space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                      color: t.textDim.withValues(alpha: 0.4), shape: const StadiumBorder()),
                ),
              ),
              SizedBox(height: Tokens.space.md),
              // What you are about to send, first.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: RepaintBoundary(
                    key: _card,
                    child: OrchardStoryCard(
                        games: widget.games,
                        level: widget.level,
                        trunkName: trunkGroupName,
                        styles: widget.styles),
                  ),
                ),
              ),
              SizedBox(height: Tokens.space.lg),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('share-out'),
                  onPressed: _sharing ? null : _shareImage,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.text,
                    foregroundColor: t.bg,
                    shape: const StadiumBorder(),
                    textStyle: TextStyle(
                        fontFamily: Tokens.type.ui,
                        fontSize: Tokens.type.body, fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  label: Text(_sharing ? 'Opening...' : 'Share image'),
                ),
              ),
              SizedBox(height: Tokens.space.lg),
              // The link: a separate, deliberate act, private until switched.
              MergeSemantics(
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Public link',
                            style: TextStyle(
                                fontSize: Tokens.type.body,
                                fontWeight: FontWeight.w600,
                                color: t.text)),
                        SizedBox(height: Tokens.space.xxs),
                        Text(
                          public
                              ? 'Anyone with the link can see your trees, their '
                                  'games, covers and status.'
                              : 'Off: only you can see your orchard. On: anyone '
                                  'with the link can view it. Notes and who '
                                  'recommended a game are never shared.',
                          style: TextStyle(fontSize: Tokens.type.caption, color: t.textDim),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: Tokens.space.sm),
                  _working
                      ? const SizedBox.square(
                          dimension: 28,
                          child: Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : Switch.adaptive(
                          key: const Key('share-public'),
                          value: public,
                          onChanged: _setPublic,
                        ),
                ]),
              ),
              if (_error != null) ...[
                SizedBox(height: Tokens.space.sm),
                Text(_error!,
                    style: TextStyle(fontSize: Tokens.type.caption, color: t.text)),
              ],
              AnimatedSize(
                duration: Tokens.motion.maybe(Tokens.motion.swap,
                    reduceMotion: MediaQuery.disableAnimationsOf(context)),
                curve: Tokens.motion.easeOut,
                child: !public
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: EdgeInsets.only(top: Tokens.space.sm),
                        child: Semantics(
                          button: true,
                          label: 'Copy your link, $_link',
                          excludeSemantics: true,
                          child: Material(
                            color: Tokens.cosmos.panelDeep,
                            shape: const StadiumBorder(),
                            child: InkWell(
                              key: const Key('share-copy'),
                              customBorder: const StadiumBorder(),
                              onTap: _copy,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    Tokens.space.md, Tokens.space.sm, Tokens.space.sm, Tokens.space.sm),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(_link,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: Tokens.type.caption,
                                            color: t.textDim)),
                                  ),
                                  Text(_copied ? 'Copied' : 'Copy',
                                      style: TextStyle(
                                          fontSize: Tokens.type.caption,
                                          fontWeight: FontWeight.w700,
                                          color: t.text)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
