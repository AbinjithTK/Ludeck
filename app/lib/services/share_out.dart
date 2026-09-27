// Share OUT through the system share sheet: WhatsApp, Instagram, Messages,
// anything the phone offers. Android only today, through the app's existing
// share channel (MainActivity.kt "shareOut"); where the channel has no
// handler (iOS until its side is written, tests) it returns false and the
// caller falls back to copying the link.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ShareOut {
  static const MethodChannel _channel = MethodChannel('com.ludeck.ludeck/share');

  /// Open the share sheet with [text] and, when given, [png] as the image.
  /// True when the sheet opened.
  static Future<bool> share({required String text, Uint8List? png}) async {
    try {
      String? path;
      if (png != null) {
        // The app's cache dir: MainActivity's FileProvider serves it.
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/share/ludeck_orchard.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(png, flush: true);
        path = f.path;
      }
      final ok = await _channel
          .invokeMethod<bool>('shareOut', {'text': text, 'image': path});
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
