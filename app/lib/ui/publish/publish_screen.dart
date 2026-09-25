// Publish consent: the gate before anything leaves the device.
//
// docs/FEATURES.md section 6, first bullet: "Consent first... A Private and
// Public segmented control with the consequence of each written in plain
// language, then 'Save and share'. Default private." This screen is that gate,
// and nothing else -- it does not itself talk to the network; it hands the
// already-projected payload to a SocialBackend and reports what happened.
//
// docs/DECISIONS.md: "Never gate sharing." So this screen never checks an
// entitlement and never shows a paywall. It is reachable to every user, always.
//
// PRIVACY -- the payload this screen sends is built by `toPublished()`, which
// has no field for a third party's name. This screen never reads
// `entry.recommendedBy`, `entry.note`, or a source's `channel` -- it only ever
// sees the games already reduced to `PublishedGame`.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/level.dart';
import '../../domain/season.dart';
import '../../services/social/publish_export.dart';
import '../../services/social/social_backend.dart';
import '../../state/ludeck_store.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import 'share_card.dart';

/// The publish-consent route. Reads the store and the social backend from
/// Provider, so it needs no arguments -- same pattern as ProfileScreen.
class PublishScreen extends StatelessWidget {
  const PublishScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore>();
    final backend = context.watch<SocialBackend>();
    final items = store.items ?? const <TreeItem>[];
    final games = <PublishedGame>[
      for (final b in store.branches)
        ...toPublishedForBranch(items, store, b),
    ];
    final level = levelFor(summarise(items).harvested).level;

    return PublishBody(
      backend: backend,
      games: games,
      level: level,
    );
  }
}

/// Reduce one branch's placed items to their public form. Kept here rather than
/// inside `toPublished` (services/social/publish_export.dart) because which
/// items belong to which branch is a STORE question, not a privacy question --
/// `toPublished` itself only ever sees items and a branch name, never the store.
List<PublishedGame> toPublishedForBranch(
  List<TreeItem> items,
  LudeckStore store,
  Branch branch,
) {
  final idsOnBranch = store.placements[branch.id] ?? const <int>[];
  final onBranch =
      items.where((i) => idsOnBranch.contains(i.game.igdbId));
  return toPublished(onBranch, branch.name);
}

enum _Visibility { private, public }

/// Everything on the publish screen except where its data comes from.
/// Presentational and injectable, so a widget test can drive it with a fake
/// backend and no store.
class PublishBody extends StatefulWidget {
  const PublishBody({
    super.key,
    required this.backend,
    required this.games,
    required this.level,
  });

  final SocialBackend backend;
  final List<PublishedGame> games;
  final int level;

  @override
  State<PublishBody> createState() => _PublishBodyState();
}

class _PublishBodyState extends State<PublishBody> {
  // Default PRIVATE. docs/FEATURES.md is explicit about this default, and it is
  // decided here at the call site, never inside SocialBackend.publish -- the
  // backend takes whatever `isPublic` it is given.
  _Visibility _visibility = _Visibility.private;
  bool _saving = false;
  String? _error;

  // Distinct from `_visibility`: a PRIVATE save still confirms and still lands
  // on ShareCardScreen (FEATURES.md's "Save and share" is total for both
  // segments) -- it is only the copy-link section within that screen which
  // depends on whether a link actually exists. `_savedPublic` and `_saved`
  // being conflated into one bool was the original bug here: "saved" and "made
  // public" are two different facts, and treating them as one meant a private
  // save never reached its own confirmation screen.
  bool _saved = false;
  bool _savedPublic = false;

  bool get _signedIn => widget.backend.currentProfile != null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_signedIn) {
        await widget.backend.signIn();
      }
      await widget.backend.publish(
        games: widget.games,
        level: widget.level,
        isPublic: _visibility == _Visibility.public,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
        _savedPublic = _visibility == _Visibility.public;
      });
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(e);
      });
    }
  }

  String _messageFor(SocialException e) {
    switch (e.failure) {
      case SocialFailure.notConfigured:
        return "Sharing isn't set up yet on this build. Nothing left this "
            'device.';
      case SocialFailure.offline:
        return "Couldn't reach the network. Nothing was shared.";
      case SocialFailure.unauthorized:
        return 'Sign-in was needed and did not complete.';
      case SocialFailure.malformed:
      case SocialFailure.notFound:
        return 'Something went wrong on our side. Nothing was shared.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return ShareCardScreen(
        games: widget.games,
        level: widget.level,
        // Empty handle when the save was private -- ShareCardScreen reads an
        // empty handle as "no live link" and shows the private confirmation
        // instead of a copy-link button. See its `_hasLink` doc.
        handle: _savedPublic
            ? (widget.backend.currentProfile?.handle ?? '')
            : '',
      );
    }

    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      appBar: AppBar(
        backgroundColor: Tokens.palette.bg,
        foregroundColor: Tokens.palette.text,
        title: Text(
          'Share your tree',
          style: TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
        ),
      ),
      body: CosmosBackdrop(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(Tokens.space.md),
            children: [
              _VisibilityControl(
                value: _visibility,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _visibility = v),
              ),
              SizedBox(height: Tokens.space.md),
              if (_error != null) ...[
                SoftCard(
                  deep: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Tokens.palette.text, fontSize: Tokens.type.caption),
                  ),
                ),
                SizedBox(height: Tokens.space.md),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving
                      ? 'Saving...'
                      // "Save and share" is the exact wording FEATURES.md
                      // specifies for the CTA, regardless of which segment is
                      // selected -- taking a tree private is also a save.
                      : 'Save and share'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Private / Public, each with its consequence spelled out. Not just two labels
/// -- a segmented control alone leaves "what does Public actually do" to guessed
/// icon language, and this is a one-way disclosure to the whole internet.
class _VisibilityControl extends StatelessWidget {
  const _VisibilityControl({required this.value, required this.onChanged});

  final _Visibility value;
  final ValueChanged<_Visibility>? onChanged;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _SegmentButton(
                    label: 'Private',
                    selected: value == _Visibility.private,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(_Visibility.private),
                  ),
                ),
                SizedBox(width: Tokens.space.xs),
                Expanded(
                  child: _SegmentButton(
                    label: 'Public',
                    selected: value == _Visibility.public,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(_Visibility.public),
                  ),
                ),
              ],
            ),
            SizedBox(height: Tokens.space.sm),
            Text(
              value == _Visibility.private
                  ? 'Only you can see your tree. Nothing leaves this device.'
                  : 'Anyone with your link can view your tree: its games, '
                      'covers, your status and ratings. Your notes and who '
                      'recommended each game are never shared.',
              style: TextStyle(
                fontSize: Tokens.type.caption,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: '$label visibility',
        excludeSemantics: true,
        child: Material(
          color: selected
              ? Tokens.palette.accent.withValues(alpha: 0.18)
              : Tokens.cosmos.panelDeep,
          borderRadius: BorderRadius.circular(Tokens.radius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radius.pill),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: Tokens.palette.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
