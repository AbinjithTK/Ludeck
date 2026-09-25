import 'package:flutter/material.dart';

import 'tokens.dart';

/// How much space the floating bottom chrome occupies over the content layer.
///
/// There is deliberately no `top` here any more. The header used to float over
/// the content and the content padded itself by a computed header height, which
/// shipped broken: the sum assumed a single line of display type, and the header
/// is two lines that can each wrap. A first attempt at fixing it by MEASURING
/// the text was still wrong, because the height depends on the font, the text
/// scale and the available width, so any number computed away from the real
/// layout is a guess that happens to be close.
///
/// The header is now an ordinary layout sibling above the content, so it cannot
/// overlap it at any text size and no arithmetic is involved. What remains here
/// is the bottom band, where the value really is fixed: a round control of a
/// known diameter, a known distance off the bottom edge.
@immutable
class ChromeMetrics {
  const ChromeMetrics({required this.bottom});

  /// Space to keep clear at the bottom: safe area, the add control, and the same
  /// gap again so the last row is not touching the button that covers it.
  final double bottom;

  factory ChromeMetrics.of(BuildContext context) => ChromeMetrics(
        bottom: MediaQuery.of(context).padding.bottom +
            Tokens.space.md +
            Tokens.size.control +
            Tokens.space.md,
      );
}
