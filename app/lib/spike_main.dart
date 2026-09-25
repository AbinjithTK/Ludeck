// SPIKE entry point -- run with:
//   flutter run -t lib/spike_main.dart --enable-flutter-gpu
//
// Deliberately separate from `main.dart` so the flutter_scene gate can be driven
// on a real device without wiring an experimental screen into the app's own
// startup path. Delete alongside `ui/tree/spike/` once the 3D decision is made.

import 'package:flutter/material.dart';

import 'ui/tree/spike/scene_spike.dart';

void main() => runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SceneSpikeScreen(),
      ),
    );
