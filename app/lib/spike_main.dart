// 3D scene entry point -- run with:
//   flutter run -t lib/spike_main.dart --enable-flutter-gpu
//
// Now drives the PRODUCTION `TreeScene3D` with a handful of sample games, so the
// orbit/zoom/pan and the upright billboarded covers can be verified on a real
// device. Kept separate from `main.dart` because the 3D path is behind
// `kTree3DEnabled` and not yet wired into the app's startup.

import 'package:flutter/material.dart';

import 'data/enums.dart';
import 'data/models.dart';
import 'ui/tree/tree_scene_3d.dart';

TreeItem _item(int id, String title, {bool harvested = false}) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: harvested ? Progress.finished : Progress.untouched,
      ),
      copies: const [],
    );

void main() => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TreeScene3D(
            items: [
              for (var i = 0; i < 6; i++) _item(100 + i, 'Game $i', harvested: i == 1),
            ],
          ),
        ),
      ),
    );
