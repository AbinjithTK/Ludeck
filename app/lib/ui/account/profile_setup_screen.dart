// First-run profile setup, after an account is created.
//
// Three steps, each skippable as a whole with "Later":
//   1. Your ID (checked live), your name, your tree colour and your platforms.
//   2. Who can visit: anyone, or friends only.
//   3. Find friends by ID or name, or share yours.
//
// The ID is saved when step 1 is left, not at the end, so it is claimed before
// anyone else can take it while you pick a privacy setting. `onboarded` is set
// at step 2, which is the last thing a profile needs; finding friends is an
// extra, not a requirement.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import 'account_widgets.dart';
import 'profile_fields.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  final _handle = TextEditingController();
  final _name = TextEditingController();
  String _avatar = avatarSeeds.first;
  Set<String> _platforms = {};
  final _idStatus = ValueNotifier<HandleStatus>(HandleStatus.idle);

  bool _private = false;

  final _search = TextEditingController();
  List<SocialPerson> _results = const [];
  Timer? _searchDebounce;
  final Map<String, FollowState> _followed = {};

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    final me = context.read<SocialBackend>().currentProfile;
    if (me != null) {
      _name.text = me.displayName == 'Gardener' ? '' : me.displayName;
      _avatar = me.avatarSeed != null && avatarSeeds.contains(me.avatarSeed)
          ? me.avatarSeed!
          : avatarSeeds.first;
      _platforms = {...me.platforms};
      _private = me.isPrivate;
      // A real ID already chosen is kept; the placeholder is replaced with a
      // suggestion from the name, which the person can change.
      if (me.onboarded) {
        _handle.text = me.handle;
      } else {
        final guess = normalizeHandle(me.displayName)
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        if (guess.length >= 3 && guess != 'gardener') {
          _handle.text = guess.length > 30 ? guess.substring(0, 30) : guess;
        }
      }
    }
  }

  @override
  void dispose() {
    _idStatus.dispose();
    _searchDebounce?.cancel();
    _handle.dispose();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(ProfileEdit edit, {required int thenStep}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _backend.updateProfile(edit);
      if (!mounted) return;
      setState(() => _step = thenStep);
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.failure == SocialFailure.conflict) {
          _idStatus.value = HandleStatus.taken;
          _error = 'Someone has that ID. Try another.';
        } else if (e.failure == SocialFailure.invalid) {
          _error = 'That ID is not allowed. Try another.';
        } else {
          _error = accountFailureText(e);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    switch (_step) {
      case 0:
        final name = _name.text.trim();
        if (!handleSavable(_handle.text, _idStatus.value)) {
          setState(() => _error = 'Pick an ID first.');
          return;
        }
        if (name.isEmpty) {
          setState(() => _error = 'Add the name friends know you by.');
          return;
        }
        _save(
          ProfileEdit(
            handle: normalizeHandle(_handle.text),
            displayName: name,
            avatarSeed: _avatar,
            platforms: orderedPlatforms(_platforms),
          ),
          thenStep: 1,
        );
      case 1:
        _save(ProfileEdit(isPrivate: _private, onboarded: true), thenStep: 2);
      default:
        Navigator.of(context).pop();
    }
  }

  void _onSearch(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _backend.searchPeople(q);
        if (mounted && _search.text == q) setState(() => _results = r);
      } on SocialException {
        // A failed search leaves the last results; typing again retries.
      }
    });
  }

  Future<void> _follow(SocialPerson p) async {
    try {
      final s = await _backend.setFollowing(p.handle, true);
      if (mounted) setState(() => _followed[p.handle] = s);
    } on SocialException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(accountFailureText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Tokens.space.md, vertical: Tokens.space.xs),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(right: Tokens.space.xxs),
                        child: AnimatedContainer(
                          duration: Tokens.motion.grow,
                          width: i == _step ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: i <= _step
                                ? Tokens.palette.text
                                : Tokens.cosmos.panelEdge,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (_step < 2)
                      TextButton(
                        key: const Key('setup-later'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Later',
                            style: TextStyle(color: Tokens.palette.textDim)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(Tokens.space.md),
                  child: switch (_step) {
                    0 => _identity(),
                    1 => _privacy(),
                    _ => _friends(),
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.all(Tokens.space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            key: const Key('setup-error'),
                            style: TextStyle(color: Tokens.palette.danger)),
                      ),
                      SizedBox(height: Tokens.space.sm),
                    ],
                    FilledButton(
                      key: const Key('setup-next'),
                      onPressed: _busy ? null : _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: Tokens.palette.accent,
                        foregroundColor: Tokens.palette.bg,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(switch (_step) {
                        0 => 'Next',
                        1 => 'Save',
                        _ => 'Done',
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccountTitle('Make it yours',
              body: 'Friends find you by your ID. You can change any of this '
                  'later in Settings.'),
          const FieldLabel('Your ID'),
          HandleField(controller: _handle, status: _idStatus),
          const FieldLabel('Your name'),
          TextField(
            key: const Key('setup-name'),
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: Tokens.palette.text),
            decoration: accountField(hint: 'Name').copyWith(counterText: ''),
          ),
          const FieldLabel('Your tree colour'),
          AvatarPicker(
            selected: _avatar,
            name: _name.text.isEmpty ? _handle.text : _name.text,
            onChanged: (s) => setState(() => _avatar = s),
          ),
          const FieldLabel('What you play on'),
          PlatformPicker(
            selected: _platforms,
            onChanged: (s) => setState(() => _platforms = s),
          ),
        ],
      );

  Widget _privacyCard({
    required bool value,
    required String title,
    required String body,
    required IconData icon,
  }) {
    final on = _private == value;
    return Semantics(
      button: true,
      selected: on,
      child: Card(
        color: Tokens.palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          side: BorderSide(
              color: on ? Tokens.palette.text : Tokens.cosmos.panelEdge,
              width: on ? 2 : 1),
        ),
        child: InkWell(
          key: Key(value ? 'setup-private' : 'setup-public'),
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          onTap: () => setState(() => _private = value),
          child: Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: Row(children: [
              Icon(icon, color: Tokens.palette.text),
              SizedBox(width: Tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: Tokens.palette.text,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: Tokens.space.xxs),
                    Text(body,
                        style: TextStyle(
                            color: Tokens.palette.textDim,
                            fontSize: Tokens.type.caption)),
                  ],
                ),
              ),
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: on ? Tokens.palette.text : Tokens.palette.textDim),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _privacy() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountTitle('Who can visit your orchard?',
              body: 'Your notes and who recommended a game are never shared, '
                  'whichever you pick.'),
          SizedBox(height: Tokens.space.md),
          _privacyCard(
            value: false,
            title: 'Anyone',
            body: 'Anyone with your ID or link can see your tree and follow '
                'you.',
            icon: Icons.public,
          ),
          SizedBox(height: Tokens.space.sm),
          _privacyCard(
            value: true,
            title: 'Friends only',
            body: 'People ask to follow you. They see your tree once you say '
                'yes.',
            icon: Icons.lock_outline,
          ),
        ],
      );

  Widget _friends() {
    final me = _backend.currentProfile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountTitle('Find your friends',
            body: 'Search by their ID or name. You can do this any time from '
                'Friends.'),
        SizedBox(height: Tokens.space.md),
        TextField(
          key: const Key('setup-search'),
          controller: _search,
          autocorrect: false,
          onChanged: _onSearch,
          style: TextStyle(color: Tokens.palette.text),
          decoration: accountField(hint: 'ID or name', prefix: '@'),
        ),
        SizedBox(height: Tokens.space.sm),
        for (final p in _results) _personRow(p),
        if (_search.text.length >= 2 && _results.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
            child: Text('Nobody by that ID yet.',
                style: TextStyle(color: Tokens.palette.textDim)),
          ),
        if (me != null) ...[
          SizedBox(height: Tokens.space.lg),
          OutlinedButton.icon(
            key: const Key('setup-copy-id'),
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: 'Find me on Ludeck: @${me.handle}'));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied. Paste it to a friend.')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text('Copy my ID, @${me.handle}'),
          ),
        ],
      ],
    );
  }

  Widget _personRow(SocialPerson p) {
    final state = _followed[p.handle] ?? p.iFollow;
    return ListTile(
      key: Key('setup-person-${p.handle}'),
      contentPadding: EdgeInsets.zero,
      leading: ProfileOrb(seed: p.profile.avatarSeed, name: p.profile.displayName),
      title: Text(p.profile.displayName,
          style: TextStyle(color: Tokens.palette.text)),
      subtitle: Text('@${p.handle}',
          style: TextStyle(color: Tokens.palette.textDim)),
      trailing: switch (state) {
        FollowState.none => FilledButton.tonal(
            key: Key('setup-follow-${p.handle}'),
            onPressed: () => _follow(p),
            child: const Text('Follow'),
          ),
        FollowState.pending => Text('Requested',
            style: TextStyle(color: Tokens.palette.textDim)),
        FollowState.accepted => Text('Following',
            style: TextStyle(color: Tokens.palette.text)),
      },
    );
  }
}
