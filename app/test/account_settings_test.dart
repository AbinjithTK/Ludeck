// Settings > Account and Your profile, against the fake.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/ui/account/account_settings_screen.dart';
import 'package:ludeck/ui/account/my_profile_screen.dart';

const _me = SocialProfile(
  id: 'me',
  handle: 'abin',
  displayName: 'Abin',
  avatarSeed: 'biolume',
  bio: 'cozy games',
  platforms: ['pc'],
  onboarded: true,
);

Future<void> _open(WidgetTester tester, SocialBackend b, Widget screen) async {
  tester.view.physicalSize = const Size(412, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Provider<SocialBackend>.value(
    value: b,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'),
        )),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  late FakeSocialStore store;
  late FakeSocialBackend me;

  setUp(() {
    store = FakeSocialStore();
    store.addProfile(const SocialProfile(
        id: 'a', handle: 'alice', displayName: 'Alice', onboarded: true));
    store.addProfile(const SocialProfile(
        id: 'c', handle: 'cara', displayName: 'Cara', onboarded: true));
    me = FakeSocialBackend(signedInAs: _me, store: store);
  });

  group('account settings', () {
    testWidgets('shows who you are and how you sign in', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      expect(find.text('Abin'), findsOneWidget);
      expect(find.text('@abin'), findsOneWidget);
      expect(find.text('cozy games'), findsOneWidget);
      expect(find.text('Signed in with Google'), findsOneWidget);
    });

    testWidgets('an email account says so', (tester) async {
      final b = FakeSocialBackend(store: store);
      await b.signUpWithEmail('abin@example.com', 'orchard1');
      await _open(tester, b, const AccountSettingsScreen());
      expect(find.text('Signed in with Email and password'), findsOneWidget);
      expect(find.text('abin@example.com'), findsOneWidget);
    });

    testWidgets('Friends only toggles privacy on the server', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-private');
      expect(me.currentProfile!.isPrivate, isTrue);
      expect(find.textContaining('People ask to follow you'), findsOneWidget);
      await _tap(tester, 'account-private');
      expect(me.currentProfile!.isPrivate, isFalse);
    });

    testWidgets('edit profile saves only what changed', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-edit-profile');

      await tester.enterText(find.byKey(const Key('edit-bio')), 'metroidvanias');
      await tester.enterText(find.byKey(const Key('edit-handle')), 'abin_plays');
      await tester.pump(const Duration(milliseconds: 400));
      await _tap(tester, 'edit-avatar-neon');
      await _tap(tester, 'edit-platform-switch');
      await _tap(tester, 'edit-save');

      final p = me.currentProfile!;
      expect(p.handle, 'abin_plays');
      expect(p.bio, 'metroidvanias');
      expect(p.avatarSeed, 'neon');
      expect(p.platforms, ['pc', 'switch']);
      expect(p.displayName, 'Abin');
      // Back on account settings, with the new ID.
      expect(find.text('@abin_plays'), findsOneWidget);
    });

    testWidgets('edit profile refuses a taken ID and stays open', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-edit-profile');
      await tester.enterText(find.byKey(const Key('edit-handle')), 'alice');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Someone has that ID. Try another.'), findsOneWidget);
      await _tap(tester, 'edit-save');
      expect(find.byKey(const Key('edit-error')), findsOneWidget);
      expect(me.currentProfile!.handle, 'abin');
    });

    testWidgets('blocked people can be unblocked', (tester) async {
      await me.block('cara');
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-blocked');
      expect(find.byKey(const Key('person-cara')), findsOneWidget);
      await _tap(tester, 'person-action-cara');
      expect(find.byKey(const Key('person-cara')), findsNothing);
      expect(await me.blockedPeople(), isEmpty);
    });

    testWidgets('no one blocked says so', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-blocked');
      expect(find.byKey(const Key('people-empty')), findsOneWidget);
    });

    testWidgets('sign out signs out and leaves the screen', (tester) async {
      await _open(tester, me, const AccountSettingsScreen());
      await _tap(tester, 'account-sign-out');
      expect(me.currentProfile, isNull);
      expect(find.byKey(const Key('account-sign-out')), findsNothing);
      expect(find.textContaining('still on this phone'), findsOneWidget);
    });
  });

  group('your profile', () {
    testWidgets('shows your counts to you, and who hyped what', (tester) async {
      final alice = FakeSocialBackend(signedInAs: store.profiles['a'], store: store);
      final cara = FakeSocialBackend(signedInAs: store.profiles['c'], store: store);
      await alice.setFollowing('abin', true);
      await cara.setFollowing('abin', true);
      await me.setFollowing('alice', true);
      await alice.setHype('abin', 7, true);
      await cara.setHype('abin', 7, true);

      await _open(tester, me, const MyProfileScreen(hero: SizedBox()));
      expect(find.text('Abin'), findsOneWidget);
      expect(find.text('cozy games'), findsOneWidget);
      expect(find.text('PC'), findsOneWidget);
      expect(find.bySemanticsLabel('2 followers'), findsOneWidget);
      expect(find.bySemanticsLabel('1 following'), findsOneWidget);
      expect(find.text('Only you see these numbers.'), findsOneWidget);
      expect(find.byKey(const Key('profile-hyped-7')), findsOneWidget);
      expect(find.text('Hyped by @cara and @alice'), findsOneWidget);

      await _tap(tester, 'profile-followers');
      expect(find.byKey(const Key('person-alice')), findsOneWidget);
      expect(find.byKey(const Key('person-cara')), findsOneWidget);
    });

    testWidgets('an empty profile explains itself', (tester) async {
      await _open(tester, me, const MyProfileScreen(hero: SizedBox()));
      expect(find.bySemanticsLabel('0 followers'), findsOneWidget);
      expect(find.byKey(const Key('profile-hyped-empty')), findsOneWidget);
    });
  });
}
