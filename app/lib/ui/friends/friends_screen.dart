import 'package:flutter/material.dart';

import '../gamified/primitives.dart';
import '../tokens.dart';
import '../visit/visit_screen.dart';

/// Friends: find someone by handle and open their tree.
///
/// ### What this fixes
///
/// `VisitScreen` -- reactions, following, grafting from someone else's tree --
/// was reachable from exactly ONE place: a "See what a visitor sees" button on
/// the user's own share card, four taps deep. So you could only ever visit your
/// own tree, and Follow had no screen on which following meant anything. The code
/// was built and had no door.
///
/// ### What it is NOT, yet
///
/// This is the handle door and nothing more. A followed-list needs accounts to be
/// real -- against the in-memory fake a friend is a fiction, and you would be
/// following someone who cannot exist -- so the list arrives after authentication
/// is wired. That ordering is deliberate rather than a shortcut, and the screen
/// says so in plain words instead of showing an empty list that looks broken.
///
/// No counts and no feed, per the frozen decision in `docs/DECISIONS.md`.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    // A leading @ is what a person types; it is not part of the handle.
    final handle = _controller.text.trim().replaceFirst(RegExp(r'^@'), '');
    if (handle.isEmpty) {
      setState(() => _error = 'Type a handle first.');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VisitScreen(handle: handle)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Friends',
                  style: TextStyle(
                    fontSize: Tokens.type.title,
                    letterSpacing: Tokens.type.trackingTitle,
                    color: Tokens.palette.text,
                  ),
                ),
                SizedBox(height: Tokens.space.xs),
                Text(
                  "Open someone's tree by their handle. You can react to what "
                  'they have grown, follow them, and graft a game onto your own '
                  'tree.',
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    height: Tokens.type.leadingBody,
                    color: Tokens.palette.textDim,
                  ),
                ),
                SizedBox(height: Tokens.space.lg),
                TextField(
                  controller: _controller,
                  onSubmitted: (_) => _open(),
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  style: TextStyle(color: Tokens.palette.text),
                  decoration: InputDecoration(
                    prefixText: '@',
                    prefixStyle: TextStyle(color: Tokens.palette.textDim),
                    hintText: 'handle',
                    hintStyle: TextStyle(color: Tokens.palette.textDim),
                    errorText: _error,
                    filled: true,
                    fillColor: Tokens.cosmos.panelDeep,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Tokens.radius.card),
                      borderSide: BorderSide(color: Tokens.cosmos.panelEdge),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Tokens.radius.card),
                      borderSide: BorderSide(color: Tokens.palette.accent),
                    ),
                  ),
                ),
                SizedBox(height: Tokens.space.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _open,
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.palette.accent,
                      foregroundColor: Tokens.palette.bg,
                    ),
                    child: const Text('Open their tree'),
                  ),
                ),
                SizedBox(height: Tokens.space.xl),
                Text(
                  'A list of the people you follow arrives once accounts are '
                  'real. Until then a handle is the way in.',
                  style: TextStyle(
                    fontSize: Tokens.type.caption,
                    color: Tokens.palette.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
