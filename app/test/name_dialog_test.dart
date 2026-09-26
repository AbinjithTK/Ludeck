import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/common/name_dialog.dart';

/// Regression for the on-device red screen
/// `'_dependents.isEmpty': is not true` after naming a branch: the caller used
/// to dispose the dialog's TextEditingController as soon as `showDialog`
/// returned, while the TextField was still mounted for the exit animation.
void main() {
  Future<String?> Function() mount(WidgetTester tester, {String initial = ''}) {
    String? result;
    var done = false;
    late BuildContext ctx;
    return () async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      showNameDialog(ctx,
              title: 'Name this branch',
              confirmLabel: 'Grow it',
              initial: initial)
          .then((v) {
        result = v;
        done = true;
      });
      await tester.pumpAndSettle();
      return done ? result : null;
    };
  }

  testWidgets('submit via button returns trimmed name and animates out cleanly',
      (tester) async {
    await mount(tester)();
    await tester.enterText(find.byType(TextField), '  Couch co-op  ');
    await tester.tap(find.text('Grow it'));
    // Step through the whole exit animation frame by frame: the old bug threw
    // mid-animation, not at the end.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NameDialog), findsNothing);
  });

  testWidgets('keyboard submit closes without an exception', (tester) async {
    await mount(tester)();
    await tester.enterText(find.byType(TextField), 'Story nights');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NameDialog), findsNothing);
  });

  testWidgets('cancel and blank input both return null', (tester) async {
    String? got = 'unset';
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    showNameDialog(ctx, title: 't', confirmLabel: 'OK').then((v) => got = v);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(got, isNull);
    expect(tester.takeException(), isNull);

    got = 'unset';
    showNameDialog(ctx, title: 't', confirmLabel: 'OK').then((v) => got = v);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets('rename prefills the current name', (tester) async {
    String? got;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    showNameDialog(ctx,
            title: 'Rename branch', confirmLabel: 'Rename', initial: 'Cozy')
        .then((v) => got = v);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cozy'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Cozy nights');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(got, 'Cozy nights');
    expect(tester.takeException(), isNull);
  });
}
