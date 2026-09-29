// Settings > Account, for a signed-in person: who you are, who can visit,
// who you have blocked, how you sign in, sign out, and delete the account.
//
// Delete is Google Play's in-app account deletion requirement. The flow moved
// here from the bottom of the profile screen unchanged in what it says and
// does: it removes the public side (orchard, reactions, follows, seeds) and
// leaves the games on the phone alone.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/activity_recorder.dart';
import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import 'account_widgets.dart';
import 'my_profile_screen.dart';
import 'profile_fields.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _busy = false;
  StreamSubscription<SocialAuthEvent>? _auth;

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    _auth = context.read<SocialBackend>().authChanges.listen((e) {
      if (mounted) setState(() {});
    });
    // The row may have been edited on another phone; read it fresh.
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await _backend.refreshMyProfile();
    } on SocialException {
      // Offline: show what we have.
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _setPrivate(bool value) async {
    setState(() => _busy = true);
    try {
      await _backend.updateProfile(ProfileEdit(isPrivate: value));
    } on SocialException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(accountFailureText(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _backend.signOut();
      messenger?.showSnackBar(const SnackBar(
          content: Text('Signed out. Your games are still on this phone.')));
      nav.pop();
    } on SocialException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(accountFailureText(e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This removes your public orchard, your reactions, follows and '
            'seeds, and your account from our server. It cannot be undone. '
            'The games on this phone stay exactly as they are.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Keep account')),
          TextButton(
            key: const Key('confirm-delete-account'),
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: Tokens.palette.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _backend.deleteAccount();
      messenger?.showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')));
      nav.pop();
    } on SocialException {
      messenger?.showSnackBar(const SnackBar(
          content: Text('Could not delete right now. Nothing was removed.')));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen))
      .then((_) {
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) {
    final me = _backend.currentProfile;
    final method = _backend.signInMethod;
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: me == null
              ? _signedOut()
              : ListView(
                  padding: EdgeInsets.all(Tokens.space.md),
                  children: [
                    Row(children: [
                      BackButton(color: Tokens.palette.text),
                      const AccountTitle('Account'),
                    ]),
                    SizedBox(height: Tokens.space.md),
                    _header(me),
                    SizedBox(height: Tokens.space.md),
                    _row(
                      key: 'account-edit-profile',
                      icon: Icons.edit_outlined,
                      title: 'Edit profile',
                      subtitle: 'Name, ID, bio, tree colour, platforms',
                      onTap: () => _push(const EditProfileScreen()),
                    ),
                    _row(
                      key: 'account-public-profile',
                      icon: Icons.person_outline,
                      title: 'Your profile',
                      subtitle: 'Your orchard as friends see it',
                      onTap: () => _push(const MyProfileScreen()),
                    ),
                    SizedBox(height: Tokens.space.md),
                    _section('Privacy'),
                    Material(
                      color: Tokens.palette.surface,
                      borderRadius: BorderRadius.circular(Tokens.radius.card),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        key: const Key('account-private'),
                        value: me.isPrivate,
                        onChanged: _busy ? null : _setPrivate,
                        title: Text('Friends only',
                            style: TextStyle(color: Tokens.palette.text)),
                        subtitle: Text(
                          me.isPrivate
                              ? 'People ask to follow you. They see your tree '
                                  'once you say yes.'
                              : 'Anyone with your ID or link can see your tree.',
                          style: TextStyle(
                              color: Tokens.palette.textDim,
                              fontSize: Tokens.type.caption),
                        ),
                      ),
                    ),
                    SizedBox(height: Tokens.space.xs),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Tokens.space.xs),
                      child: Text(
                        'Your notes and who recommended a game are never '
                        'shared.',
                        style: TextStyle(
                            color: Tokens.palette.textDim,
                            fontSize: Tokens.type.caption),
                      ),
                    ),
                    SizedBox(height: Tokens.space.sm),
                    Material(
                      color: Tokens.palette.surface,
                      borderRadius: BorderRadius.circular(Tokens.radius.card),
                      clipBehavior: Clip.antiAlias,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: ActivitySharing.enabled,
                        builder: (context, on, _) => SwitchListTile(
                          key: const Key('account-share-activity'),
                          value: on,
                          onChanged: ActivitySharing.set,
                          title: Text('Show friends what I play',
                              style: TextStyle(color: Tokens.palette.text)),
                          subtitle: Text(
                            'When you plant, finish or rate a game, it shows '
                            'in their Lately list. Title, cover and rating '
                            'only.',
                            style: TextStyle(
                                color: Tokens.palette.textDim,
                                fontSize: Tokens.type.caption),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: Tokens.space.sm),
                    _row(
                      key: 'account-blocked',
                      icon: Icons.block,
                      title: 'Blocked people',
                      subtitle: "They can't find you or see your tree",
                      onTap: () => _push(const BlockedPeopleScreen()),
                    ),
                    SizedBox(height: Tokens.space.md),
                    _section('Sign-in'),
                    _row(
                      key: 'account-method',
                      icon: method?.provider == 'google'
                          ? Icons.account_circle_outlined
                          : Icons.mail_outline,
                      title: method == null
                          ? 'Signed in'
                          : 'Signed in with ${method.label}',
                      subtitle: method?.email ?? '',
                    ),
                    SizedBox(height: Tokens.space.lg),
                    OutlinedButton(
                      key: const Key('account-sign-out'),
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                    SizedBox(height: Tokens.space.xs),
                    TextButton(
                      key: const Key('account-delete'),
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(
                          foregroundColor: Tokens.palette.danger),
                      child: const Text('Delete account'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _signedOut() => Padding(
        padding: EdgeInsets.all(Tokens.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackButton(color: Tokens.palette.text),
            const AccountTitle('Signed out',
                body: 'Your games are still on this phone.'),
          ],
        ),
      );

  Widget _header(SocialProfile me) => Row(children: [
        ProfileOrb(seed: me.avatarSeed, name: me.displayName, diameter: 64),
        SizedBox(width: Tokens.space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.displayName,
                  key: const Key('account-name'),
                  style: TextStyle(
                      fontFamily: Tokens.type.displayFamily,
                      fontSize: Tokens.type.title,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.text)),
              Text('@${me.handle}',
                  key: const Key('account-handle'),
                  style: TextStyle(color: Tokens.palette.textDim)),
              if (me.bio.isNotEmpty) ...[
                SizedBox(height: Tokens.space.xxs),
                Text(me.bio, style: TextStyle(color: Tokens.palette.text)),
              ],
            ],
          ),
        ),
      ]);

  Widget _section(String title) => Padding(
        padding: EdgeInsets.only(
            left: Tokens.space.xs, bottom: Tokens.space.xs),
        child: Text(title,
            style: TextStyle(
                color: Tokens.palette.textDim,
                fontSize: Tokens.type.caption,
                fontWeight: FontWeight.w600)),
      );

  Widget _row({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: ListTile(
          key: Key(key),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radius.card)),
          tileColor: Tokens.palette.surface,
          leading: Icon(icon, color: Tokens.palette.text),
          title: Text(title, style: TextStyle(color: Tokens.palette.text)),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle,
                  style: TextStyle(
                      color: Tokens.palette.textDim,
                      fontSize: Tokens.type.caption)),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: Tokens.palette.textDim),
          onTap: onTap,
        ),
      );
}

/// Change name, ID, bio, tree colour and platforms. Saves only what changed.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final SocialProfile _start;
  late final _handle = TextEditingController(text: _start.handle);
  late final _name = TextEditingController(text: _start.displayName);
  late final _bio = TextEditingController(text: _start.bio);
  late String _avatar = avatarSeeds.contains(_start.avatarSeed)
      ? _start.avatarSeed!
      : avatarSeeds.first;
  late Set<String> _platforms = {..._start.platforms};
  final _idStatus = ValueNotifier<HandleStatus>(HandleStatus.idle);
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = context.read<SocialBackend>().currentProfile!;
  }

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _bio.dispose();
    _idStatus.dispose();
    super.dispose();
  }

  ProfileEdit _changes() {
    final handle = normalizeHandle(_handle.text);
    final name = _name.text.trim();
    final bio = _bio.text.trim();
    final platforms = orderedPlatforms(_platforms);
    return ProfileEdit(
      handle: handle == _start.handle ? null : handle,
      displayName: name == _start.displayName ? null : name,
      bio: bio == _start.bio ? null : bio,
      avatarSeed: _avatar == _start.avatarSeed ? null : _avatar,
      platforms: platforms.join(',') == _start.platforms.join(',')
          ? null
          : platforms,
    );
  }

  Future<void> _save() async {
    if (!handleSavable(_handle.text, _idStatus.value)) {
      setState(() => _error = 'Pick an ID first.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Add the name friends know you by.');
      return;
    }
    final edit = _changes();
    if (edit.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<SocialBackend>().updateProfile(edit);
      messenger?.showSnackBar(const SnackBar(content: Text('Saved.')));
      nav.pop();
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.failure == SocialFailure.conflict) {
          _idStatus.value = HandleStatus.taken;
          _error = 'Someone has that ID. Try another.';
        } else if (e.failure == SocialFailure.invalid) {
          _error = "One of those can't be saved. Check your ID and bio.";
        } else {
          _error = accountFailureText(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CosmosBackdrop(
          sky: Sky.deep,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Tokens.space.xs),
                  child: Row(children: [
                    BackButton(color: Tokens.palette.text),
                    const Expanded(child: AccountTitle('Edit profile')),
                    TextButton(
                      key: const Key('edit-save'),
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.all(Tokens.space.md),
                    children: [
                      Center(
                        child: ProfileOrb(
                            seed: _avatar, name: _name.text, diameter: 80),
                      ),
                      const FieldLabel('Name'),
                      TextField(
                        key: const Key('edit-name'),
                        controller: _name,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: Tokens.palette.text),
                        decoration:
                            accountField(hint: 'Name').copyWith(counterText: ''),
                      ),
                      const FieldLabel('ID'),
                      HandleField(
                          controller: _handle,
                          status: _idStatus,
                          keyPrefix: 'edit'),
                      Padding(
                        padding: EdgeInsets.only(top: Tokens.space.xxs),
                        child: Text(
                          'Changing your ID changes your link. Old links stop '
                          'working.',
                          style: TextStyle(
                              color: Tokens.palette.textDim,
                              fontSize: Tokens.type.caption),
                        ),
                      ),
                      const FieldLabel('Bio'),
                      TextField(
                        key: const Key('edit-bio'),
                        controller: _bio,
                        maxLength: 160,
                        maxLines: 3,
                        minLines: 2,
                        style: TextStyle(color: Tokens.palette.text),
                        decoration: accountField(
                            hint: 'One line about what you play'),
                      ),
                      const FieldLabel('Tree colour'),
                      AvatarPicker(
                        selected: _avatar,
                        name: _name.text,
                        keyPrefix: 'edit',
                        onChanged: (s) => setState(() => _avatar = s),
                      ),
                      const FieldLabel('What you play on'),
                      PlatformPicker(
                        selected: _platforms,
                        keyPrefix: 'edit',
                        onChanged: (s) => setState(() => _platforms = s),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: Tokens.space.md),
                        Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              key: const Key('edit-error'),
                              style: TextStyle(color: Tokens.palette.danger)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A list of people loaded once, with an action per row.
class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({
    super.key,
    required this.title,
    required this.load,
    required this.empty,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Future<List<SocialProfile>> Function() load;
  final String empty;
  final String? actionLabel;

  /// Runs the row's action; the row disappears when it completes.
  final Future<void> Function(SocialProfile p)? onAction;

  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<SocialProfile>? _people;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.load();
      if (mounted) setState(() => _people = p);
    } on SocialException catch (e) {
      if (mounted) setState(() => _error = accountFailureText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(Tokens.space.md),
            children: [
              Row(children: [
                BackButton(color: Tokens.palette.text),
                AccountTitle(widget.title),
              ]),
              SizedBox(height: Tokens.space.md),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Tokens.palette.danger))
              else if (people == null)
                Center(
                    child: CircularProgressIndicator(
                        color: Tokens.palette.textDim))
              else if (people.isEmpty)
                Text(widget.empty,
                    key: const Key('people-empty'),
                    style: TextStyle(color: Tokens.palette.textDim))
              else
                for (final p in people)
                  ListTile(
                    key: Key('person-${p.handle}'),
                    contentPadding: EdgeInsets.zero,
                    leading:
                        ProfileOrb(seed: p.avatarSeed, name: p.displayName),
                    title: Text(p.displayName,
                        style: TextStyle(color: Tokens.palette.text)),
                    subtitle: Text('@${p.handle}',
                        style: TextStyle(color: Tokens.palette.textDim)),
                    trailing: widget.onAction == null
                        ? null
                        : OutlinedButton(
                            key: Key('person-action-${p.handle}'),
                            onPressed: () async {
                              try {
                                await widget.onAction!(p);
                                if (mounted) {
                                  setState(() => _people = [
                                        for (final q in people)
                                          if (q.id != p.id) q,
                                      ]);
                                }
                              } on SocialException catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text(accountFailureText(e))));
                              }
                            },
                            child: Text(widget.actionLabel ?? ''),
                          ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class BlockedPeopleScreen extends StatelessWidget {
  const BlockedPeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.read<SocialBackend>();
    return PeopleListScreen(
      title: 'Blocked people',
      load: b.blockedPeople,
      empty: "You haven't blocked anyone.",
      actionLabel: 'Unblock',
      onAction: (p) => b.unblock(p.handle),
    );
  }
}
