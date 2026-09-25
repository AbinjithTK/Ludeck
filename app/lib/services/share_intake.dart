// The Dart end of the share channel.
//
// Pull based, matching MainActivity.kt: ask on startup and again on resume.
// A cold share arrives before the engine exists, so a push from Kotlin would
// have to survive that; asking cannot.

import 'package:flutter/services.dart';

/// Reads text shared to Ludeck from another app.
abstract class ShareIntake {
  /// The pending shared text, or null when there is none.
  ///
  /// Taking it CLEARS it, so one share is acted on exactly once however many
  /// times this is called. That matters because it is called on every resume.
  Future<String?> takePending();
}

/// The real intake, over the platform channel.
class PlatformShareIntake implements ShareIntake {
  const PlatformShareIntake();

  static const MethodChannel _channel =
      MethodChannel('com.ludeck.ludeck/share');

  @override
  Future<String?> takePending() async {
    try {
      final text = await _channel.invokeMethod<String>('takePendingShare');
      if (text == null) return null;
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on MissingPluginException {
      // Desktop and test runs have no Android activity behind the channel.
      // A share is not available there, which is not an error.
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// An intake that returns whatever it was given. For tests.
class FakeShareIntake implements ShareIntake {
  FakeShareIntake([this.queued]);

  String? queued;

  int takeCount = 0;

  @override
  Future<String?> takePending() async {
    takeCount++;
    final out = queued;
    queued = null;
    return out;
  }
}
