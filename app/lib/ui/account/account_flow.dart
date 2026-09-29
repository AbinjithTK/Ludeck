// How the rest of the app reaches the account screens.
//
// `ensureAccount` is what an action that needs an account calls (publish,
// react, follow): it returns the signed-in profile, opening the account
// screen first when needed, or null when the person chose "Not now".
//
// `AuthEventsListener` sits at the top of the app for the sign-ins no screen
// is waiting for: an email confirmation link opened from the inbox, a
// password reset link, or a Google redirect that lands after the account
// screen was closed. It needs the navigator, so it takes the app's key.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import 'account_screen.dart';
import 'account_widgets.dart';
import 'profile_setup_screen.dart';

/// The signed-in profile, asking the person to sign in first if needed.
/// Null means they chose not to, which callers treat as "do nothing".
///
/// [backend] is for screens handed one directly rather than through the
/// provider; the account screens get it provided either way.
Future<SocialProfile?> ensureAccount(BuildContext context,
    {SocialBackend? backend}) async {
  final b = backend ?? context.read<SocialBackend>();
  final existing = b.currentProfile;
  if (existing != null) return existing;
  return Navigator.of(context).push<SocialProfile>(
    MaterialPageRoute(
      builder: (_) => Provider<SocialBackend>.value(
        value: b,
        child: const AccountScreen(),
      ),
    ),
  );
}

class AuthEventsListener extends StatefulWidget {
  const AuthEventsListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AuthEventsListener> createState() => _AuthEventsListenerState();
}

class _AuthEventsListenerState extends State<AuthEventsListener> {
  StreamSubscription<SocialAuthEvent>? _sub;
  bool _setupOpen = false;
  bool _passwordOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<SocialBackend>().authChanges.listen(_on);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _on(SocialAuthEvent e) async {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    switch (e.kind) {
      case SocialAuthKind.passwordRecovery:
        if (_passwordOpen) return;
        _passwordOpen = true;
        await nav.push(MaterialPageRoute<void>(
            builder: (_) => const NewPasswordScreen()));
        _passwordOpen = false;
      case SocialAuthKind.signedIn:
        // An open account screen finishes its own sign-in.
        if (AccountScreen.openCount > 0 || _setupOpen || _passwordOpen) return;
        if (e.profile == null || e.profile!.onboarded) return;
        _setupOpen = true;
        await nav.push(MaterialPageRoute<void>(
            builder: (_) => const ProfileSetupScreen()));
        _setupOpen = false;
      case SocialAuthKind.failed:
        if (AccountScreen.openCount > 0) return;
        final messenger = ScaffoldMessenger.maybeOf(nav.context);
        messenger?.showSnackBar(SnackBar(content: Text(e.message ?? '')));
      case SocialAuthKind.signedOut:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opened by a password reset link. The link has already signed the person in;
/// this sets the password they will use next time.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 6) {
      setState(() => _error = 'Use at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SocialBackend>().setNewPassword(_password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed. You are signed in.')));
      Navigator.of(context).pop();
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.failure == SocialFailure.invalid
          ? 'Pick a password you have not used here before.'
          : accountFailureText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CosmosBackdrop(
          sky: Sky.deep,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(Tokens.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BackButton(color: Tokens.palette.text),
                  ),
                  const AccountTitle('Set a new password'),
                  SizedBox(height: Tokens.space.lg),
                  TextField(
                    key: const Key('new-password'),
                    controller: _password,
                    obscureText: !_show,
                    autofocus: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _save(),
                    style: TextStyle(color: Tokens.palette.text),
                    decoration: accountField(
                      hint: 'New password',
                      error: _error,
                      helper: 'At least 6 characters',
                      suffix: IconButton(
                        tooltip: _show ? 'Hide password' : 'Show password',
                        icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                            color: Tokens.palette.textDim),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  SizedBox(height: Tokens.space.md),
                  FilledButton(
                    key: const Key('new-password-save'),
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.palette.accent,
                      foregroundColor: Tokens.palette.bg,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Save password'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
