// Asked once, at the moment a game becomes finished.
//
// A rating belongs to the HARVEST, not to the game. That is why this appears on
// the transition into finished and nowhere else on its own: a star control
// sitting permanently on every row would turn the collection into a scoring
// chore, and the one moment the answer is actually in the user's head is the
// moment they just finished playing.
//
// Skipping is a normal outcome, not an omission to chase. There is deliberately
// no unrated count, no badge, and no second prompt: an app that keeps asking
// teaches people to dismiss it without reading, which costs more than the
// missing data.
//
// One tap commits. A rating that needs a separate confirm button is friction on
// something the user is free to skip entirely.

import 'package:flutter/material.dart';

import '../tokens.dart';

/// What the user decided about a rating.
///
/// Three outcomes, and they are genuinely different, which is why this type
/// exists instead of a bare `int?`: a null return from the sheet means SKIP
/// (write nothing), while a [RatingChoice] carrying a null [rating] means CLEAR
/// (write null). Collapsing them into one nullable int made "skip" and "remove"
/// indistinguishable, and encoding clear as 0 would have handed the repository a
/// value it throws on, since ratings are 1 to 5.
@immutable
class RatingChoice {
  const RatingChoice(this.rating);

  /// 1 to 5, or null to remove an existing rating.
  final int? rating;
}

/// Asks for a rating.
///
/// Returns null when the user skipped or dismissed, in which case the caller
/// must write NOTHING. A returned [RatingChoice] is an instruction to write, and
/// a null `rating` inside it means clear.
Future<RatingChoice?> showRatingSheet(
  BuildContext context, {
  required String title,
  int? initial,
}) =>
    showModalBottomSheet<RatingChoice>(
      context: context,
      backgroundColor: Tokens.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radius.card),
        ),
      ),
      builder: (_) => _RatingSheet(title: title, initial: initial),
    );

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({required this.title, this.initial});

  final String title;

  /// A rating already on the entry, when the user reopened this to change it.
  final int? initial;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  /// Which star the finger is currently over, so the row fills as the user
  /// slides across it rather than only on release. Null when not touching.
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      // Scrolls, with nothing pinned. A fixed column here overflowed on a short
      // screen in the paywall, and large accessibility text reproduces it on any
      // screen.
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(Tokens.space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: text.titleMedium),
              SizedBox(height: Tokens.space.xxs),
              Text(
                // States what it is for and that it is optional, in that order.
                // "Optional" last, because leading with it invites a reflexive
                // dismiss before the question has been read.
                'How was it? Optional.',
                style: TextStyle(
                  fontSize: Tokens.type.caption,
                  color: Tokens.palette.textDim,
                ),
              ),
              SizedBox(height: Tokens.space.md),
              _Stars(
                filledTo: _hovered ?? widget.initial ?? 0,
                onEnter: (value) => setState(() => _hovered = value),
                onExit: () => setState(() => _hovered = null),
                onPick: (value) =>
                    Navigator.of(context).pop(RatingChoice(value)),
              ),
              SizedBox(height: Tokens.space.md),
              Row(
                children: [
                  // Skip is a plain, equal-weight action, not a greyed-out
                  // afterthought. Making it look discouraged is a way of
                  // nagging without words.
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Skip',
                      style: TextStyle(color: Tokens.palette.text),
                    ),
                  ),
                  if (widget.initial != null) ...[
                    SizedBox(width: Tokens.space.xs),
                    // Only offered when there IS a rating to remove. Showing
                    // "clear" on an unrated game would be a control that does
                    // nothing.
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(const RatingChoice(null)),
                      child: Text(
                        'Remove rating',
                        style: TextStyle(color: Tokens.palette.textDim),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five taps. Filled to [filledTo], hollow after it.
///
/// Readable by FORM as well as colour: a filled star against an outlined one
/// survives colour blindness and a greyscale screenshot, which a gold-versus-dim
/// pair on its own does not.
class _Stars extends StatelessWidget {
  const _Stars({
    required this.filledTo,
    required this.onEnter,
    required this.onExit,
    required this.onPick,
  });

  final int filledTo;
  final ValueChanged<int> onEnter;
  final VoidCallback onExit;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var value = 1; value <= 5; value++)
          Semantics(
            button: true,
            // Reads as a whole instruction on its own. "Star 3" tells a screen
            // reader user nothing about what pressing it does.
            label: 'Rate $value out of 5',
            selected: value <= filledTo,
            child: GestureDetector(
              onTapDown: (_) => onEnter(value),
              onTapCancel: onExit,
              onTap: () => onPick(value),
              child: Padding(
                // Generous padding rather than a larger glyph: the tap target
                // needs to be comfortable without the row dominating the sheet.
                padding: EdgeInsets.symmetric(
                  horizontal: Tokens.space.xs,
                  vertical: Tokens.space.xs,
                ),
                child: Icon(
                  value <= filledTo ? Icons.star : Icons.star_border,
                  size: Tokens.type.display,
                  color: value <= filledTo
                      ? Tokens.palette.accent
                      : Tokens.palette.textDim,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
