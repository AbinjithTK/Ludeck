// The pieces every people list shares: a row, a follow button that knows the
// three states, the Friends badge, and a quick preview sheet.
//
// "Friends" means mutual: you follow each other and both follows are
// accepted. It is a label on a person, not a number anywhere.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../account/account_flow.dart';
import '../account/account_widgets.dart';
import '../account/profile_fields.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';

/// A small pill. "Friends" for mutual, "Follows you" when only they follow.
class RelationBadge extends StatelessWidget {
  const RelationBadge({super.key, required this.person});

  final SocialPerson person;

  @override
  Widget build(BuildContext context) {
    final text = person.isFriend
        ? 'Friends'
        : person.followsMe
            ? 'Follows you'
            : null;
    if (text == null) return const SizedBox.shrink();
    return Container(
      key: Key('badge-${person.handle}'),
      padding: EdgeInsets.symmetric(
          horizontal: Tokens.space.xs, vertical: Tokens.space.xxs / 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        border: Border.all(
            color: person.isFriend
                ? Tokens.palette.text
                : Tokens.cosmos.panelEdge),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: Tokens.type.caption,
              color: person.isFriend
                  ? Tokens.palette.text
                  : Tokens.palette.textDim)),
    );
  }
}

/// Follow, Requested or Following. Owns its state so a list can hold many,
/// and reports each change so the list can refresh badges.
class FollowButton extends StatefulWidget {
  const FollowButton({super.key, required this.person, this.onChanged});

  final SocialPerson person;
  final ValueChanged<SocialPerson>? onChanged;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late FollowState _state = widget.person.iFollow;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (old.person.iFollow != widget.person.iFollow) {
      _state = widget.person.iFollow;
    }
  }

  Future<void> _tap() async {
    final backend = context.read<SocialBackend>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final following = _state == FollowState.none;
    if (!following) {
      // Leaving a private orchard means asking again to come back.
      final private = widget.person.profile.isPrivate;
      final sure = _state == FollowState.pending ||
          !private ||
          await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Unfollow @${widget.person.handle}?'),
                  content: const Text(
                      'Their orchard is friends only. To see it again you '
                      'will need to ask.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(c).pop(false),
                        child: const Text('Cancel')),
                    TextButton(
                        key: const Key('confirm-unfollow'),
                        onPressed: () => Navigator.of(c).pop(true),
                        child: const Text('Unfollow')),
                  ],
                ),
              ) ==
              true;
      if (!sure) return;
    }
    if (!mounted) return;
    if (backend.currentProfile == null && await ensureAccount(context) == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final next = await backend.setFollowing(widget.person.handle, following);
      if (!mounted) return;
      setState(() => _state = next);
      widget.onChanged?.call(widget.person.copyWith(iFollow: next));
    } on SocialException catch (e) {
      messenger?.showSnackBar(SnackBar(
          content: Text(e.failure == SocialFailure.forbidden
              ? "You can't follow @${widget.person.handle}."
              : accountFailureText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_state) {
      FollowState.none => widget.person.followsMe ? 'Follow back' : 'Follow',
      FollowState.pending => 'Requested',
      FollowState.accepted => 'Following',
    };
    final key = Key('follow-${widget.person.handle}');
    return _state == FollowState.none
        ? FilledButton(
            key: key,
            onPressed: _busy ? null : _tap,
            style: FilledButton.styleFrom(
              backgroundColor: Tokens.palette.text,
              foregroundColor: Tokens.palette.bg,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label),
          )
        : OutlinedButton(
            key: key,
            onPressed: _busy ? null : _tap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Tokens.palette.text,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label),
          );
  }
}

/// One person in a list. Tap for the preview; the button follows.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    this.trailing,
    this.onChanged,
  });

  final SocialPerson person;

  /// Replaces the follow button (a request row shows Accept and Decline).
  final Widget? trailing;
  final ValueChanged<SocialPerson>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = person.profile;
    final me = context.read<SocialBackend>().currentProfile;
    return ListTile(
      key: Key('person-${p.handle}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => showPersonPreview(context, person, onChanged: onChanged),
      leading: ProfileOrb(seed: p.avatarSeed, name: p.displayName),
      title: Text(p.displayName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Tokens.palette.text)),
      subtitle: Wrap(
        spacing: Tokens.space.xs,
        runSpacing: Tokens.space.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('@${p.handle}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Tokens.palette.textDim)),
          if (p.isPrivate)
            Semantics(
              label: 'Friends only',
              child: Icon(Icons.lock_outline,
                  size: 12, color: Tokens.palette.textDim),
            ),
          RelationBadge(person: person),
        ],
      ),
      trailing: trailing ??
          (me != null && me.id == p.id
              ? null
              : FollowButton(person: person, onChanged: onChanged)),
    );
  }
}

/// A quick look at someone before opening their orchard.
Future<void> showPersonPreview(BuildContext context, SocialPerson person,
    {ValueChanged<SocialPerson>? onChanged}) {
  final backend = context.read<SocialBackend>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Provider<SocialBackend>.value(
      value: backend,
      child: _Preview(person: person, onChanged: onChanged),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.person, this.onChanged});

  final SocialPerson person;
  final ValueChanged<SocialPerson>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = person.profile;
    final me = context.read<SocialBackend>().currentProfile;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.lg, 0, Tokens.space.lg, Tokens.space.lg),
        child: Column(
          key: const Key('person-preview'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ProfileOrb(seed: p.avatarSeed, name: p.displayName, diameter: 56),
              SizedBox(width: Tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName,
                        style: TextStyle(
                            fontFamily: Tokens.type.displayFamily,
                            fontSize: Tokens.type.title,
                            fontWeight: FontWeight.w700,
                            color: Tokens.palette.text)),
                    Text('@${p.handle}',
                        style: TextStyle(color: Tokens.palette.textDim)),
                  ],
                ),
              ),
              RelationBadge(person: person),
            ]),
            if (p.bio.isNotEmpty) ...[
              SizedBox(height: Tokens.space.sm),
              Text(p.bio, style: TextStyle(color: Tokens.palette.text)),
            ],
            if (p.platforms.isNotEmpty) ...[
              SizedBox(height: Tokens.space.sm),
              Text(
                [for (final x in p.platforms) platformLabels[x] ?? x].join(', '),
                style: TextStyle(
                    color: Tokens.palette.textDim,
                    fontSize: Tokens.type.caption),
              ),
            ],
            if (p.isPrivate && person.iFollow != FollowState.accepted) ...[
              SizedBox(height: Tokens.space.sm),
              Text(
                'Friends only. Ask to follow and they can let you in.',
                style: TextStyle(color: Tokens.palette.textDim),
              ),
            ],
            SizedBox(height: Tokens.space.md),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('preview-open'),
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute<void>(
                        builder: (_) => VisitScreen(handle: p.handle)));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Tokens.palette.accent,
                    foregroundColor: Tokens.palette.bg,
                  ),
                  icon: const Icon(Icons.park_outlined),
                  label: const Text('See their orchard'),
                ),
              ),
              if (me == null || me.id != p.id) ...[
                SizedBox(width: Tokens.space.sm),
                FollowButton(person: person, onChanged: onChanged),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
