// The account flow end to end against the fake: sign up, sign in, the email
// link, password reset, the Google failure path, and first-run setup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/ui/account/account_flow.dart';
import 'package:ludeck/ui/account/profile_setup_screen.dart';
import 'package:ludeck/ui/gamified/primitives.dart';

/// Holds what ensureAccount returned, so a test can assert on it.
class _Result {
  SocialProfile? profile;
  bool returned = false;
}

Future<_Result> _pump(WidgetTester tester, FakeSocialBackend backend) async {
  final result = _Result();
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(Provider<SocialBackend>.value(
    value: backend,
    child: AuthEventsListener(
      navigatorKey: nav,
      child: MaterialApp(
        navigatorKey: nav,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result.profile = await ensureAccount(context);
                  result.returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('setup-handle-status'))).data!;

void main() {
  late FakeSocialStore store;
  late FakeSocialBackend backend;

  setUp(() {
    store = FakeSocialStore();
    store.addProfile(const SocialProfile(
        id: 'a', handle: 'alice', displayName: 'Alice', onboarded: true));
    store.addProfile(const SocialProfile(
        id: 'b',
        handle: 'bob',
        displayName: 'Bob',
        isPrivate: true,
        onboarded: true));
    backend = FakeSocialBackend(store: store);
  });

  testWidgets('email sign-up runs setup and returns an onboarded profile',
      (tester) async {
    final result = await _pump(tester, backend);

    await _tap(tester, 'account-toggle-mode');
    expect(find.text('Create your account'), findsOneWidget);
    await _type(tester, 'account-email', 'Abin@Example.com');
    await _type(tester, 'account-password', 'orchard1');
    await _tap(tester, 'account-submit');
    await tester.pumpAndSettle();

    // Setup, step 1. The name came from the email, and suggests an ID.
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    await _type(tester, 'setup-handle', 'alice');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_status(tester), contains('Someone has that ID'));

    await _type(tester, 'setup-handle', 'abin');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_status(tester), contains('@abin is yours'));

    await _type(tester, 'setup-name', 'Abin');
    await _tap(tester, 'setup-avatar-twilight');
    await _tap(tester, 'setup-platform-pc');
    await _tap(tester, 'setup-platform-switch');
    await _tap(tester, 'setup-next');

    // Step 2: privacy.
    expect(find.text('Who can visit your orchard?'), findsOneWidget);
    await _tap(tester, 'setup-private');
    await _tap(tester, 'setup-next');

    // Step 3: find friends. Bob is private, so a follow is a request.
    await _type(tester, 'setup-search', 'bo');
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, 'setup-follow-bob');
    expect(find.text('Requested'), findsOneWidget);
    await _tap(tester, 'setup-next');
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    final me = result.profile!;
    expect(me.handle, 'abin');
    expect(me.displayName, 'Abin');
    expect(me.avatarSeed, 'twilight');
    expect(me.platforms, ['pc', 'switch']);
    expect(me.isPrivate, isTrue);
    expect(me.onboarded, isTrue);
    expect(await backend.following(), ['bob']);
  });

  testWidgets('a taken ID at save time is reported, not swallowed',
      (tester) async {
    await _pump(tester, backend);
    await _tap(tester, 'account-toggle-mode');
    await _type(tester, 'account-email', 'x@example.com');
    await _type(tester, 'account-password', 'orchard1');
    await _tap(tester, 'account-submit');
    await tester.pumpAndSettle();

    await _type(tester, 'setup-handle', 'newname');
    await tester.pump(const Duration(milliseconds: 400));
    // Someone else takes it between the check and the save.
    store.addProfile(
        const SocialProfile(id: 'z', handle: 'newname', displayName: 'Z'));
    await _type(tester, 'setup-name', 'X');
    await _tap(tester, 'setup-next');

    expect(find.byKey(const Key('setup-error')), findsOneWidget);
    expect(find.text('Who can visit your orchard?'), findsNothing);
  });

  testWidgets('with confirmations on, the email link finishes sign-up',
      (tester) async {
    store.requireEmailConfirmation = true;
    await _pump(tester, backend);
    await _tap(tester, 'account-toggle-mode');
    await _type(tester, 'account-email', 'new@example.com');
    await _type(tester, 'account-password', 'orchard1');
    await _tap(tester, 'account-submit');
    await tester.pumpAndSettle();

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.textContaining('new@example.com'), findsOneWidget);

    // Signing in before opening the link is refused with a clear reason.
    expect(backend.signInWithEmail('new@example.com', 'orchard1'),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'f', SocialFailure.emailNotConfirmed)));

    backend.openConfirmationLink('new@example.com');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
  });

  testWidgets('a wrong password says so', (tester) async {
    await backend.signUpWithEmail('ada@example.com', 'orchard1');
    await backend.signOut();

    await _pump(tester, backend);
    await _type(tester, 'account-email', 'ada@example.com');
    await _type(tester, 'account-password', 'wrongpass');
    await _tap(tester, 'account-submit');
    await tester.pumpAndSettle();

    expect(find.text("That email and password don't match."), findsOneWidget);
    expect(backend.currentProfile, isNull);
  });

  testWidgets('an email that already has an account points to sign in',
      (tester) async {
    await backend.signUpWithEmail('ada@example.com', 'orchard1');
    await backend.signOut();

    await _pump(tester, backend);
    await _tap(tester, 'account-toggle-mode');
    await _type(tester, 'account-email', 'ada@example.com');
    await _type(tester, 'account-password', 'orchard1');
    await _tap(tester, 'account-submit');
    await tester.pumpAndSettle();

    expect(find.text('That email already has an account. Sign in instead.'),
        findsOneWidget);
  });

  testWidgets('forgot password sends a link; the link sets a new password',
      (tester) async {
    await backend.signUpWithEmail('ada@example.com', 'orchard1');
    await backend.signOut();

    await _pump(tester, backend);
    await _type(tester, 'account-email', 'ada@example.com');
    await _tap(tester, 'account-forgot');
    await tester.pumpAndSettle();
    await _tap(tester, 'reset-send');
    await tester.pumpAndSettle();
    expect(store.resetRequests, ['ada@example.com']);
    expect(find.textContaining('reset link is on its way'), findsOneWidget);

    // Leave the account screen, then open the link from the inbox.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await _tap(tester, 'account-not-now');
    await tester.pumpAndSettle();
    backend.openResetLink('ada@example.com');
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsOneWidget);
    await _type(tester, 'new-password', 'newtrees2');
    await _tap(tester, 'new-password-save');
    await tester.pumpAndSettle();

    await backend.signOut();
    expect((await backend.signInWithEmail('ada@example.com', 'newtrees2')).id,
        isNotNull);
  });

  testWidgets('Google sign-in works and skips setup for a finished profile',
      (tester) async {
    final result = await _pump(tester, backend);
    await _tap(tester, 'account-google');
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    expect(result.profile!.onboarded, isTrue);
    expect(find.byType(ProfileSetupScreen), findsNothing);
  });

  testWidgets('a failed Google hand-off shows a message on the screen',
      (tester) async {
    await _pump(tester, backend);
    backend.failSignIn('Google sign-in took too long. Try again.');
    await tester.pumpAndSettle();
    expect(find.text('Google sign-in took too long. Try again.'), findsOneWidget);
  });

  testWidgets('Not now returns null and leaves the app signed out',
      (tester) async {
    final result = await _pump(tester, backend);
    await _tap(tester, 'account-not-now');
    await tester.pumpAndSettle();
    expect(result.returned, isTrue);
    expect(result.profile, isNull);
    expect(backend.currentProfile, isNull);
  });

  testWidgets('the sky fills the whole screen, however short the form',
      (tester) async {
    // 2026-09-29, on device: a Scaffold body is loose in height, so the
    // backdrop shrank to the form and bare background showed below it.
    // A Pixel 8 screen, tall enough that the form ends above the bottom.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await _pump(tester, backend);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final sky = tester.getSize(find.byType(CosmosBackdrop).last);
    expect(sky.height, screen.height);
    expect(sky.width, screen.width);
  });

  testWidgets('a build without accounts says so and offers only Not now',
      (tester) async {
    await _pump(tester, FakeSocialBackend(configured: false, store: store));
    expect(find.text('Accounts are off on this build'), findsOneWidget);
    expect(find.byKey(const Key('account-google')), findsNothing);
    expect(find.byKey(const Key('account-not-now')), findsOneWidget);
  });

  testWidgets('an email link opened with no screen waiting still runs setup',
      (tester) async {
    store.requireEmailConfirmation = true;
    await backend.signUpWithEmail('late@example.com', 'orchard1');
    await _pump(tester, backend);
    await _tap(tester, 'account-not-now');
    await tester.pumpAndSettle();

    backend.openConfirmationLink('late@example.com');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
  });
}
