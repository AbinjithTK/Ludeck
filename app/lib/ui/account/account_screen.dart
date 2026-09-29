// Sign in and sign up, on one screen.
//
// Google, or an email and password. The account is optional: "Not now" leaves
// the app exactly as it works offline, and nothing on the phone depends on
// signing in. Only the social layer (sharing, friends, seeds) needs one.
//
// The screen does not trust the button that started a sign-in to also finish
// it. A Google hand-off and an email link both come back through
// SocialBackend.authChanges, sometimes minutes later, so that stream is what
// moves the screen on. That is also how an expired Google hand-off
// (bad_oauth_state) becomes a message here instead of a browser 404.
//
// After a first sign-in the profile is not onboarded yet (its ID is the
// placeholder 'g...'), so setup runs before the screen hands the profile back.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_backend.dart';
import '../gamified/primitives.dart';
import '../tokens.dart';
import 'account_widgets.dart';
import 'profile_setup_screen.dart';

enum _Mode { signIn, signUp }

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.firstRun = false, this.onDone});

  /// Shown straight after the intro. Changes the copy only.
  final bool firstRun;

  /// Called with the profile, or null for "Not now". Defaults to popping the
  /// route with that value.
  final ValueChanged<SocialProfile?>? onDone;

  /// How many are on screen. The app-wide auth listener leaves sign-ins to an
  /// open account screen, so setup is never opened twice for one sign-in.
  static int openCount = 0;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _waitingForGoogle = false;
  bool _showPassword = false;
  bool _finishing = false;
  String? _error;

  /// Set once a confirmation email is on its way.
  String? _checkEmail;

  StreamSubscription<SocialAuthEvent>? _auth;

  SocialBackend get _backend => context.read<SocialBackend>();

  @override
  void initState() {
    super.initState();
    AccountScreen.openCount++;
    _auth = context.read<SocialBackend>().authChanges.listen((e) {
      if (!mounted) return;
      if (e.kind == SocialAuthKind.signedIn && e.profile != null) {
        _finish(e.profile!);
      } else if (e.kind == SocialAuthKind.failed) {
        setState(() {
          _waitingForGoogle = false;
          _busy = false;
          _error = e.message;
        });
      }
    });
  }

  @override
  void dispose() {
    AccountScreen.openCount--;
    _auth?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _done(SocialProfile? p) {
    if (widget.onDone != null) {
      widget.onDone!(p);
    } else {
      Navigator.of(context).pop(p);
    }
  }

  Future<void> _finish(SocialProfile profile) async {
    if (_finishing) return;
    _finishing = true;
    var p = profile;
    if (!p.onboarded) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ProfileSetupScreen(),
      ));
      if (!mounted) return;
      p = _backend.currentProfile ?? p;
    }
    _done(p);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on SocialException catch (e) {
      if (!mounted) return;
      setState(() => _error = accountFailureText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _waitingForGoogle = true;
      _error = null;
    });
    try {
      final p = await _backend.signIn();
      if (mounted) await _finish(p);
    } on SocialException catch (e) {
      if (!mounted || !_waitingForGoogle) return;
      setState(() {
        _waitingForGoogle = false;
        _error = accountFailureText(e);
      });
    }
  }

  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Type your email address.';
    }
    if (_password.text.length < 6) {
      return 'Use at least 6 characters for your password.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _run(() async {
      final email = _email.text.trim();
      if (_mode == _Mode.signIn) {
        final p = await _backend.signInWithEmail(email, _password.text);
        if (mounted) await _finish(p);
        return;
      }
      final outcome = await _backend.signUpWithEmail(email, _password.text);
      if (!mounted) return;
      if (outcome == SignUpOutcome.checkEmail) {
        setState(() => _checkEmail = email);
      } else if (_backend.currentProfile != null) {
        await _finish(_backend.currentProfile!);
      }
    });
  }

  Future<void> _forgot() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ResetDialog(initial: _email.text.trim()),
    );
    if (email == null || email.isEmpty || !mounted) return;
    await _run(() async {
      await _backend.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'If that email has an account, a reset link is on its way. '
            'Open it on this phone.'),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.read<SocialBackend>();
    return PopScope(
      canPop: widget.onDone == null,
      child: Scaffold(
        body: CosmosBackdrop(
          sky: Sky.deep,
          // Expand: a Scaffold body is loose in height, and a scroll view on
          // a short form shrinks to the form, so the sky stopped halfway down
          // and the bare background showed under it (2026-09-29, on device).
          child: SizedBox.expand(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: Tokens.space.lg),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: kToolbarHeight,
                            child: widget.onDone == null &&
                                    Navigator.of(context).canPop()
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child:
                                        BackButton(color: Tokens.palette.text),
                                  )
                                : null,
                          ),
                          const Spacer(),
                          Center(
                            child: GlowOrb(
                              diameter: 72,
                              glow: 0.7,
                              child: Icon(Icons.park_outlined,
                                  size: 32, color: Tokens.palette.text),
                            ),
                          ),
                          SizedBox(height: Tokens.space.md),
                          if (!backend.isConfigured)
                            _notConfigured()
                          else if (_checkEmail != null)
                            _checkInbox()
                          else if (_waitingForGoogle)
                            _waiting()
                          else
                            _form(),
                          const Spacer(flex: 2),
                          TextButton(
                            key: const Key('account-not-now'),
                            onPressed: () => _done(null),
                            child: Text(
                              'Not now',
                              style: TextStyle(color: Tokens.palette.textDim),
                            ),
                          ),
                          SizedBox(height: Tokens.space.sm),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notConfigured() => const AccountTitle(
        'Accounts are off on this build',
        body: 'Everything still works on this phone. Sharing and friends '
            'need a build with accounts turned on.',
      );

  Widget _waiting() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountTitle(
            'Finish in the browser',
            body: 'Pick your Google account there. You will come straight '
                'back here.',
          ),
          SizedBox(height: Tokens.space.lg),
          Center(child: CircularProgressIndicator(color: Tokens.palette.accent)),
          SizedBox(height: Tokens.space.lg),
          OutlinedButton(
            key: const Key('account-cancel-google'),
            onPressed: () => setState(() => _waitingForGoogle = false),
            child: const Text('Cancel'),
          ),
        ],
      );

  Widget _checkInbox() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountTitle(
            'Check your inbox',
            body: 'We sent a link to $_checkEmail. Open it on this phone and '
                'you will be signed in.',
          ),
          if (_error != null) ...[
            SizedBox(height: Tokens.space.sm),
            _errorText(),
          ],
          SizedBox(height: Tokens.space.lg),
          OutlinedButton(
            key: const Key('account-resend'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await _backend.resendConfirmation(_checkEmail!);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sent it again.')));
                    }),
            child: const Text('Send it again'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _checkEmail = null;
              _mode = _Mode.signIn;
            }),
            child: const Text('Use a different email'),
          ),
        ],
      );

  Widget _errorText() => Semantics(
        liveRegion: true,
        child: Text(
          _error!,
          key: const Key('account-error'),
          style: TextStyle(color: Tokens.palette.danger, fontSize: Tokens.type.body),
        ),
      );

  Widget _form() {
    final signUp = _mode == _Mode.signUp;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountTitle(
            signUp ? 'Create your account' : 'Sign in to Ludeck',
            body: widget.firstRun
                ? 'Share your orchard, follow friends and send them games. '
                    'Your collection stays on this phone either way.'
                : 'Your collection stays on this phone. An account adds '
                    'sharing, friends and seeds.',
          ),
          SizedBox(height: Tokens.space.lg),
          FilledButton.icon(
            key: const Key('account-google'),
            onPressed: _busy ? null : _google,
            style: FilledButton.styleFrom(
              backgroundColor: Tokens.palette.text,
              foregroundColor: Tokens.palette.bg,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continue with Google'),
          ),
          SizedBox(height: Tokens.space.md),
          Row(children: [
            Expanded(child: Divider(color: Tokens.cosmos.panelEdge)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Tokens.space.sm),
              child: Text('or use email',
                  style: TextStyle(
                      color: Tokens.palette.textDim,
                      fontSize: Tokens.type.caption)),
            ),
            Expanded(child: Divider(color: Tokens.cosmos.panelEdge)),
          ]),
          SizedBox(height: Tokens.space.md),
          TextField(
            key: const Key('account-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: TextStyle(color: Tokens.palette.text),
            decoration: accountField(hint: 'Email'),
          ),
          SizedBox(height: Tokens.space.sm),
          TextField(
            key: const Key('account-password'),
            controller: _password,
            obscureText: !_showPassword,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: [
              signUp ? AutofillHints.newPassword : AutofillHints.password
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: Tokens.palette.text),
            decoration: accountField(
              hint: 'Password',
              helper: signUp ? 'At least 6 characters' : null,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: Tokens.palette.textDim,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: Tokens.space.sm),
            _errorText(),
          ],
          SizedBox(height: Tokens.space.md),
          FilledButton(
            key: const Key('account-submit'),
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: Tokens.palette.accent,
              foregroundColor: Tokens.palette.bg,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Tokens.palette.bg))
                : Text(signUp ? 'Create account' : 'Sign in'),
          ),
          SizedBox(height: Tokens.space.xs),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: const Key('account-toggle-mode'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _mode = signUp ? _Mode.signIn : _Mode.signUp;
                          _error = null;
                        }),
                child: Text(signUp ? 'I have an account' : 'New here? Create one'),
              ),
              if (!signUp)
                TextButton(
                  key: const Key('account-forgot'),
                  onPressed: _busy ? null : _forgot,
                  child: const Text('Forgot password?'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Asks for the email to send a reset link to. Its own State, so the field's
/// controller lives until the dialog has finished closing.
class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.initial});

  final String initial;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reset your password'),
        content: TextField(
          key: const Key('reset-email'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: Tokens.palette.text),
          decoration: accountField(hint: 'you@example.com'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('reset-send'),
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      );
}
