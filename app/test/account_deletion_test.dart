import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/services/social/supabase_social_backend.dart';
import 'package:ludeck/ui/account/account_settings_screen.dart';
import 'package:ludeck/ui/profile/profile_screen.dart';
import 'package:provider/provider.dart';

/// Google Play's in-app account deletion, and the handle the server trigger
/// assigns (migration 0002). The server half runs against a real Supabase
/// project in docs/DEPLOY-COMMUNITY.md step 7; this proves the app half.
void main() {
  group('handleFor matches migration 0002 handle_for', () {
    test("'g' plus the first ten hex digits of the uuid", () {
      expect(handleFor('3F2504E0-4F89-11D3-9A0C-0305E82C3301'), 'g3f2504e04f');
    });

    test('always passes the profiles.handle check', () {
      final check = RegExp(r'^[a-z0-9_]{3,30}$');
      for (final id in [
        '00000000-0000-0000-0000-000000000000',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        'a1b2c3d4-e5f6-4711-8899-aabbccddeeff',
      ]) {
        expect(check.hasMatch(handleFor(id)), isTrue, reason: id);
      }
    });
  });

  group('deleteAccount', () {
    setUp(FakeSocialBackend.resetShared);

    test('removes the published orchard and signs out', () async {
      final b = FakeSocialBackend();
      final me = await b.signIn();
      await b.publish(games: const [
        PublishedGame(
            igdbId: 1, title: 'Hades', status: Progress.finished, branchName: 'Cozy'),
      ], level: 2, isPublic: true);
      expect((await b.treeByHandle(me.handle)).games, hasLength(1));

      await b.deleteAccount();

      expect(b.currentProfile, isNull);
      await expectLater(b.treeByHandle(me.handle), throwsA(isA<SocialException>()));
    });

    test('requires being signed in', () async {
      await expectLater(FakeSocialBackend().deleteAccount(),
          throwsA(isA<SocialException>()));
    });
  });

  group('the account settings control', () {
    setUp(FakeSocialBackend.resetShared);

    Future<void> pump(WidgetTester tester, SocialBackend backend) async {
      tester.view.physicalSize = const Size(412, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Provider<SocialBackend>.value(
        value: backend,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AccountSettingsScreen())),
              child: const Text('open'),
            )),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the profile shows no account control when signed out',
        (tester) async {
      await tester.pumpWidget(Provider<SocialBackend>.value(
        value: FakeSocialBackend(),
        child: MaterialApp(
          home: ProfileBody(items: const [], branches: 0, hero: Container()),
        ),
      ));
      expect(find.byKey(const Key('profile-account')), findsNothing);
    });

    testWidgets('delete asks first and keeping changes nothing', (tester) async {
      final b = FakeSocialBackend();
      await b.signIn();
      await pump(tester, b);
      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      await tester.tap(find.text('Keep account'));
      await tester.pumpAndSettle();
      expect(b.currentProfile, isNotNull);
    });

    testWidgets('confirming deletes the account and leaves the screen',
        (tester) async {
      final b = FakeSocialBackend();
      await b.signIn();
      await pump(tester, b);
      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-account')));
      await tester.pumpAndSettle();
      expect(b.currentProfile, isNull);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
      expect(find.byKey(const Key('account-delete')), findsNothing);
    });
  });
}