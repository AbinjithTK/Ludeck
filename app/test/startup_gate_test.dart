// Regression test for a real bug found on-device during Stage 8 verification,
// not by any test until now: _StartupGate's onDone callback was
// `() => setState(() => _seen = Future.value(true))`, an arrow body whose
// value is the assignment's own value -- a Future. That gives the inner
// closure an INFERRED return type of Future<bool> instead of void, which
// setState asserts against and throws on at runtime. It compiled clean and
// every OnboardingScreen widget test passed, because none of them drove
// onDone through _StartupGate's actual wiring -- only through a test-supplied
// mock callback. This test mounts LudeckApp itself, so a regression here
// would be caught the same way a real device tap caught it.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeSocialBackend.resetShared();
  });

  testWidgets(
      'a fresh install shows onboarding, and tapping through to Get started '
      'reaches the real home screen without a setState exception',
      (tester) async {
    late Repository repo;
    await tester.runAsync(() async {
      repo = await Repository.openInMemory();
    });
    addTearDown(() => repo.close());

    await tester.runAsync(() async {
      await tester.pumpWidget(LudeckApp(
        repo: repo,
        social: FakeSocialBackend(configured: false),
      ));
    });
    await tester.pumpAndSettle();

    expect(find.text('Your games, as a roadmap'), findsOneWidget);

    while (find.text('Next').evaluate().isNotEmpty) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // No exception was thrown by the tap -- this is the actual assertion the
    // original bug fails. FlutterError.onError rethrows in test mode, so a
    // regression here fails the test rather than just logging.
    expect(tester.takeException(), isNull);

    // And onboarding is genuinely gone, replaced by the real home screen.
    expect(find.text('Your games, as a roadmap'), findsNothing);
  });
}
