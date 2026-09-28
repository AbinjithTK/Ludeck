// The type system is real, not a fallback.
//
// A font family the engine cannot find falls back to the platform face
// SILENTLY: no error, no warning, the app just looks like it did before.
// These tests are what notice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('both families are declared and every file they name is bundled', () {
    for (final family in [Tokens.type.ui, Tokens.type.displayFamily]) {
      expect(pubspec, contains('- family: $family'),
          reason: '$family is used by the app but not declared in pubspec.yaml');
    }
    final assets = RegExp(r'- asset: (assets/fonts/\S+\.ttf)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toList();
    expect(assets, hasLength(7));
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: '$a is declared but missing');
      // A static cut is ~90KB; an HTML error page saved as .ttf is not.
      expect(File(a).lengthSync(), greaterThan(40000), reason: a);
    }
  });

  test('the OFL licences ship with the fonts', () {
    expect(File('assets/fonts/OFL-PlusJakartaSans.txt').existsSync(), isTrue);
    expect(File('assets/fonts/OFL-BricolageGrotesque.txt').existsSync(), isTrue);
  });

  test('every headline-size style names the display face', () {
    // A display- or title-size TextStyle without a family inherits the UI
    // face, and the hierarchy quietly flattens back to one face.
    final size = RegExp(r'fontSize: Tokens\.type\.(display|title)\b');
    final misses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!size.hasMatch(lines[i])) continue;
        final from = i - 5 < 0 ? 0 : i - 5;
        final to = i + 6 > lines.length ? lines.length : i + 6;
        if (!lines.sublist(from, to).join('\n').contains('fontFamily')) {
          misses.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(misses, isEmpty);
  });

  test('every button text style names the UI face', () {
    // ButtonStyle.textStyle REPLACES the theme's label style instead of
    // merging with it, so a button with its own style and no family drew
    // "Share your orchard" in Roboto (seen on device, 2026-09-28).
    final misses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('textStyle: TextStyle(')) continue;
        final to = i + 4 > lines.length ? lines.length : i + 4;
        if (!lines.sublist(i, to).join('\n').contains('fontFamily')) {
          misses.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(misses, isEmpty);
  });
}
