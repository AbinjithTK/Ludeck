/// The ONLY status vocabulary in this app, ported from BUILD.md section 4.
///
/// Two orthogonal axes, not one chain. A single chain cannot express "I
/// finished it and then sold it", which is a normal collector state, and it
/// forces a sale to destroy the completion record.
///
/// Each value carries TWO labels. `label` is plain language. `tree` is the
/// metaphor word from DESIGN.md. The metaphor is a display layer: what is
/// persisted is `name`, so the metaphor can change without a migration.
library;

/// Do I have it?
enum Ownership {
  /// Seen and saved, not owned. Someone recommended it, or it came off a clip.
  /// This is the state the judged tie-break criterion is about.
  spotted('Spotted', 'Seed'),
  owned('Owned', 'On the tree'),

  /// Sold, traded, refunded, or lapsed out of a subscription.
  released('Let go', 'Given away');

  const Ownership(this.label, this.tree);
  final String label;
  final String tree;
}

/// How far did I get?
///
/// The labels are deliberately not verdicts. "Set aside" carries the same data
/// a harsher word would and costs the user nothing to look at, which matters in
/// an app whose whole subject is games you have not played yet.
enum Progress {
  /// Tree word is 'Growing', not 'Ripe'. Ripeness was removed on 2026-09-24:
  /// it asked the user to learn what a colour meant, and `choosePick` answers
  /// the same question in a sentence instead. `Season.stillGrowing` counts this
  /// state alongside installed and playing, so the word matches the rollup.
  untouched('Not started', 'Growing'),
  installed('Installed', 'Within reach'),
  playing('Playing', 'In hand'),
  finished('Finished', 'Harvested'),

  /// Not the same event as finishing. This is where the interesting data lives.
  abandoned('Set aside', 'Pressed');

  const Progress(this.label, this.tree);
  final String label;
  final String tree;
}

/// Digital or a physical object on a shelf. Physical is what makes `released`
/// honest: you can hold it, so you can hand it away.
enum Form {
  digital('Digital'),
  physical('Physical');

  const Form(this.label);
  final String label;
}

/// How the copy was acquired. Subscription matters: it can lapse and remove
/// access without the user doing anything.
enum Acquired {
  bought('Bought'),
  subscription('Subscription'),
  gift('Gift'),
  bundle('Bundle'),
  free('Free');

  const Acquired(this.label);
  final String label;
}

/// A platform a copy can live on. Each becomes a branch on the tree, and a
/// branch only exists when at least one copy sits on it, so a PC-only player
/// never sees empty scaffolding.
///
/// Order is deliberate: it is the order branches are laid out, lowest first.
enum Platform {
  pc('PC'),
  playstation('PlayStation 5'),
  xbox('Xbox'),
  switch_('Nintendo Switch'),
  steamDeck('Steam Deck'),
  quest('Meta Quest'),
  android('Android'),
  ios('iOS');

  const Platform(this.label);
  final String label;

  static Platform? fromName(String raw) {
    final n = raw.toLowerCase().trim();
    for (final p in Platform.values) {
      if (p.name.toLowerCase() == n || p.label.toLowerCase() == n) return p;
    }
    return null;
  }
}
