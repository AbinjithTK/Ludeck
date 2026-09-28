// The sheet shown when something is shared to Ludeck.
//
// Nothing enters the library unseen. High confidence candidates arrive already
// ticked so one tap still adds everything, but the user always sees what was
// understood. Silent writes from arbitrary shared text would fill the library
// with games from messages that were about nothing of the kind, and a library
// you cannot trust is worse than no feature.
//
// Scrolls, with the action pinned. A fixed column here overflowed on a short
// screen once already in the paywall, and large accessibility text reproduces it
// on any screen.

import 'package:flutter/material.dart';

import '../../domain/resolve.dart';
import '../../services/share_resolver.dart';
import '../tokens.dart';

/// What the user decided.
class IntakeChoice {
  const IntakeChoice({required this.accepted, this.recommendedBy});

  /// The candidates the user left ticked. May be empty when they only wanted
  /// the link kept.
  final List<Candidate> accepted;

  /// Who put this on their radar. Optional, typed by the user: Android does not
  /// tell us who sent a share, and guessing would be worse than asking.
  final String? recommendedBy;
}

/// Shows the sheet. Returns null when dismissed without a decision.
Future<IntakeChoice?> showIntakeSheet(
  BuildContext context,
  ShareResolution resolution,
) =>
    showModalBottomSheet<IntakeChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radius.card),
        ),
      ),
      builder: (_) => _IntakeSheet(resolution: resolution),
    );

class _IntakeSheet extends StatefulWidget {
  const _IntakeSheet({required this.resolution});

  final ShareResolution resolution;

  @override
  State<_IntakeSheet> createState() => _IntakeSheetState();
}

class _IntakeSheetState extends State<_IntakeSheet> {
  late final Set<int> _ticked;
  final TextEditingController _recommender = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-tick by confidence. Anything below the threshold is still listed so
    // the user can see it was considered, just not chosen for them.
    _ticked = {
      for (var i = 0; i < widget.resolution.candidates.length; i++)
        if (widget.resolution.candidates[i].shouldAutoTick) i,
    };
  }

  @override
  void dispose() {
    _recommender.dispose();
    super.dispose();
  }

  List<Candidate> get _candidates => widget.resolution.candidates;

  bool get _anyTicked => _ticked.isNotEmpty;

  void _submit() {
    final accepted = [
      for (var i = 0; i < _candidates.length; i++)
        if (_ticked.contains(i)) _candidates[i],
    ];
    final by = _recommender.text.trim();
    Navigator.of(context).pop(IntakeChoice(
      accepted: accepted,
      recommendedBy: by.isEmpty ? null : by,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasCandidates = _candidates.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Tokens.space.md,
          right: Tokens.space.md,
          top: Tokens.space.md,
          // Keeps the action clear of the keyboard when the recommender field
          // has focus.
          bottom: Tokens.space.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Grabber(),
            SizedBox(height: Tokens.space.sm),
            Text(
              hasCandidates ? 'Add to your collection' : 'Nothing recognised',
              style: TextStyle(
                color: Tokens.palette.text,
                fontFamily: Tokens.type.displayFamily,
                fontSize: Tokens.type.title,
                height: Tokens.type.leadingTitle,
                letterSpacing: Tokens.type.trackingTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: Tokens.space.xxs),
            Text(
              _subtitle(hasCandidates),
              style: TextStyle(
                color: Tokens.palette.textDim,
                fontSize: Tokens.type.caption,
                height: Tokens.type.leadingBody,
              ),
            ),
            SizedBox(height: Tokens.space.md),

            // The list scrolls; the action below does not move.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _candidates.length; i++)
                      _CandidateRow(
                        candidate: _candidates[i],
                        ticked: _ticked.contains(i),
                        onChanged: (on) => setState(() {
                          if (on) {
                            _ticked.add(i);
                          } else {
                            _ticked.remove(i);
                          }
                        }),
                      ),
                    if (hasCandidates) SizedBox(height: Tokens.space.sm),
                    if (hasCandidates) _RecommenderField(_recommender),
                  ],
                ),
              ),
            ),

            SizedBox(height: Tokens.space.md),
            _Action(
              label: _actionLabel(hasCandidates),
              enabled: _anyTicked || !hasCandidates,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(bool hasCandidates) {
    if (hasCandidates) {
      final n = _candidates.length;
      return n == 1
          ? 'One game found in what you shared.'
          : '$n games found in what you shared.';
    }
    if (widget.resolution.hasKeepableLink) {
      // Deliberately does NOT offer to keep the link. A source row hangs off a
      // game (sources.igdb_id is NOT NULL), so there is nowhere to put a link
      // with no game behind it yet. Offering to keep it would be a button that
      // promises storage that does not exist. See Phase F in docs\TASKS.md.
      return 'That link could not be matched to a game yet. Searching by name '
          'is the way in for now.';
    }
    return 'Nothing in that text looked like a game. You can search for one '
        'instead.';
  }

  String _actionLabel(bool hasCandidates) {
    if (!hasCandidates) return 'Search instead';
    final n = _ticked.length;
    if (n == 0) return 'Nothing selected';
    return n == 1 ? 'Add 1 game' : 'Add $n games';
  }
}

class _Grabber extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Tokens.palette.textDim,
            borderRadius: BorderRadius.circular(Tokens.radius.pill),
          ),
        ),
      );
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.ticked,
    required this.onChanged,
  });

  final Candidate candidate;
  final bool ticked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The plain label, never the metaphor word: the metaphor is a display
      // layer and a screen reader announcing 'Growing' explains nothing.
      label: '${candidate.title}, ${candidate.method.label}',
      checked: ticked,
      child: InkWell(
        onTap: () => onChanged(!ticked),
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
          child: Row(
            children: [
              Checkbox(
                value: ticked,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: Tokens.palette.accent,
                checkColor: Tokens.palette.bg,
                side: BorderSide(color: Tokens.palette.textDim),
              ),
              SizedBox(width: Tokens.space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      style: TextStyle(
                        color: Tokens.palette.text,
                        fontSize: Tokens.type.body,
                        height: Tokens.type.leadingBody,
                      ),
                    ),
                    Text(
                      candidate.method.label,
                      style: TextStyle(
                        color: Tokens.palette.textDim,
                        fontSize: Tokens.type.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommenderField extends StatelessWidget {
  const _RecommenderField(this.controller);

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: TextStyle(
          color: Tokens.palette.text,
          fontSize: Tokens.type.body,
        ),
        decoration: InputDecoration(
          labelText: 'Who recommended it? Optional',
          labelStyle: TextStyle(
            color: Tokens.palette.textDim,
            fontSize: Tokens.type.caption,
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Tokens.palette.textDim),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Tokens.palette.accent),
          ),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.palette.accent,
            foregroundColor: Tokens.palette.bg,
            disabledBackgroundColor: Tokens.palette.surface,
            disabledForegroundColor: Tokens.palette.textDim,
            padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radius.card),
            ),
          ),
          child: Text(label, style: TextStyle(fontSize: Tokens.type.body)),
        ),
      );
}
