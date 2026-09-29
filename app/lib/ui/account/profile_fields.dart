// The profile fields setup and Edit profile share: the ID with its live
// availability check, the tree-colour avatar, and platform chips. One copy, so
// the rules and the copy cannot drift between the two screens.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../tokens.dart';
import 'account_widgets.dart';

const platformLabels = {
  'pc': 'PC',
  'switch': 'Switch',
  'ps5': 'PS5',
  'ps4': 'PS4',
  'xbox': 'Xbox',
  'mobile': 'Mobile',
  'steamdeck': 'Steam Deck',
  'other': 'Other',
};

const avatarLabels = {
  'biolume': 'Glow',
  'twilight': 'Sunset',
  'neon': 'Neon',
  'midnight': 'Night',
};

enum HandleStatus { idle, checking, free, taken, invalid, offline }

/// Whether [status] lets the ID be saved. Offline is allowed: the server
/// checks again on save and answers with a conflict if it is taken.
bool handleSavable(String raw, HandleStatus status) =>
    handleLooksValid(raw) &&
    status != HandleStatus.taken &&
    status != HandleStatus.invalid;

/// The @ID field. Checks availability 350ms after typing stops, and only the
/// newest reply may paint, so a slow answer for "ab" never overwrites "abin".
/// [status] is owned by the parent so a save that meets a conflict can mark
/// the ID taken.
class HandleField extends StatefulWidget {
  const HandleField({
    super.key,
    required this.controller,
    required this.status,
    this.keyPrefix = 'setup',
  });

  final TextEditingController controller;
  final ValueNotifier<HandleStatus> status;
  final String keyPrefix;

  @override
  State<HandleField> createState() => _HandleFieldState();
}

class _HandleFieldState extends State<HandleField> {
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.controller.text.isNotEmpty) _check(widget.controller.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _check(String raw) {
    _debounce?.cancel();
    if (!handleLooksValid(raw)) {
      widget.status.value = raw.isEmpty ? HandleStatus.idle : HandleStatus.invalid;
      return;
    }
    widget.status.value = HandleStatus.checking;
    final seq = ++_seq;
    final backend = context.read<SocialBackend>();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      HandleStatus next;
      try {
        next = await backend.isHandleAvailable(raw)
            ? HandleStatus.free
            : HandleStatus.taken;
      } on SocialException {
        next = HandleStatus.offline;
      }
      if (mounted && seq == _seq) widget.status.value = next;
    });
  }

  String _message(HandleStatus s) => switch (s) {
        HandleStatus.idle => '3 to 30 letters, numbers or _',
        HandleStatus.checking => 'Checking',
        HandleStatus.free =>
          '@${normalizeHandle(widget.controller.text)} is yours if you want it',
        HandleStatus.taken => 'Someone has that ID. Try another.',
        HandleStatus.invalid => 'Use 3 to 30 letters, numbers or _',
        HandleStatus.offline =>
          "Couldn't check right now. We'll check when you save.",
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HandleStatus>(
        valueListenable: widget.status,
        builder: (context, s, _) {
          final color = switch (s) {
            HandleStatus.free => Tokens.palette.text,
            HandleStatus.taken || HandleStatus.invalid => Tokens.palette.danger,
            _ => Tokens.palette.textDim,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: Key('${widget.keyPrefix}-handle'),
                controller: widget.controller,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 30,
                onChanged: _check,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_@]')),
                ],
                style: TextStyle(color: Tokens.palette.text),
                decoration: accountField(hint: 'yourid', prefix: '@').copyWith(
                  counterText: '',
                  suffixIcon: switch (s) {
                    HandleStatus.checking => Padding(
                        padding: EdgeInsets.all(Tokens.space.sm),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Tokens.palette.textDim)),
                      ),
                    HandleStatus.free =>
                      Icon(Icons.check_circle, color: Tokens.palette.text),
                    HandleStatus.taken || HandleStatus.invalid =>
                      Icon(Icons.error_outline, color: Tokens.palette.danger),
                    _ => null,
                  },
                ),
              ),
              SizedBox(height: Tokens.space.xxs),
              Semantics(
                liveRegion: true,
                child: Text(_message(s),
                    key: Key('${widget.keyPrefix}-handle-status'),
                    style: TextStyle(
                        fontSize: Tokens.type.caption, color: color)),
              ),
            ],
          );
        },
      );
}

/// The four tree colours, each an orb with the person's initial.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.selected,
    required this.name,
    required this.onChanged,
    this.keyPrefix = 'setup',
  });

  final String selected;
  final String name;
  final ValueChanged<String> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Tokens.space.sm,
        children: [
          for (final seed in avatarSeeds)
            Semantics(
              button: true,
              selected: seed == selected,
              label: '${avatarLabels[seed]} tree colour',
              child: GestureDetector(
                key: Key('$keyPrefix-avatar-$seed'),
                onTap: () => onChanged(seed),
                child: Column(children: [
                  ProfileOrb(
                    seed: seed,
                    name: name,
                    diameter: 52,
                    selected: seed == selected,
                  ),
                  SizedBox(height: Tokens.space.xxs),
                  Text(avatarLabels[seed]!,
                      style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: seed == selected
                              ? Tokens.palette.text
                              : Tokens.palette.textDim)),
                ]),
              ),
            ),
        ],
      );
}

class PlatformPicker extends StatelessWidget {
  const PlatformPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'setup',
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Tokens.space.xs,
        runSpacing: Tokens.space.xs,
        children: [
          for (final p in profilePlatforms)
            FilterChip(
              key: Key('$keyPrefix-platform-$p'),
              label: Text(platformLabels[p]!),
              selected: selected.contains(p),
              onSelected: (on) =>
                  onChanged(on ? ({...selected, p}) : ({...selected}..remove(p))),
            ),
        ],
      );
}

/// The selected platforms in the canonical order the server stores.
List<String> orderedPlatforms(Set<String> s) =>
    [for (final p in profilePlatforms) if (s.contains(p)) p];

/// A small label above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: Tokens.space.md, bottom: Tokens.space.xs),
        child: Text(text,
            style: TextStyle(
                color: Tokens.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: Tokens.type.body)),
      );
}
