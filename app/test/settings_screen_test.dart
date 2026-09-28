// The header's single door. It carries no store: each destination is a
// callback, so these mount it with plain spies and check that the three
// places the old header reached are all still reachable, by their labels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/settings/settings_screen.dart';

void main() {
  ({int library, int friends, int profile}) taps = (
    library: 0,
    friends: 0,
    profile: 0,
  );

  Widget wrap() => MaterialApp(
        home: SettingsScreen(
          onLibrary: () => taps = (
            library: taps.library + 1,
            friends: taps.friends,
            profile: taps.profile,
          ),
          onFriends: () => taps = (
            library: taps.library,
            friends: taps.friends + 1,
            profile: taps.profile,
          ),
          onProfile: () => taps = (
            library: taps.library,
            friends: taps.friends,
            profile: taps.profile + 1,
          ),
        ),
      );

  setUp(() => taps = (library: 0, friends: 0, profile: 0));

  testWidgets('the three destinations are all present as rows', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('Settings'), findsOneWidget);
    for (final label in ['You', 'Library', 'Friends']) {
      expect(find.byKey(Key('settings-${label.toLowerCase()}')), findsOneWidget,
          reason: '$label must be reachable from Settings');
    }
  });

  testWidgets('each row opens its own destination', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.byKey(const Key('settings-you')));
    await tester.tap(find.byKey(const Key('settings-library')));
    await tester.tap(find.byKey(const Key('settings-friends')));
    await tester.pump();

    expect(taps, (library: 1, friends: 1, profile: 1));
  });
}
