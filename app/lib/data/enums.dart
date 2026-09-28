/// The ONLY status vocabulary in this app, ported from BUILD.md section 4.
///
/// Two orthogonal axes, not one chain. A single chain cannot express "I
/// finished it and then sold it", which is a normal collector state, and it
/// forces a sale to destroy the completion record.
///
/// Each value carries TWO labels. `label` is plain language, and it is what
/// the app SHOWS (2026-09-28, Abin: "say what a person can understand easily,
/// real actions, instead of things like harvested"). `tree` is the metaphor
/// word from DESIGN.md, kept only as reference for the art (a harvested fruit
/// is gold, a bud is a closed flower) and never put in front of the user.
/// What is persisted is `name`, so either can change without a migration.
library;

/// Do I have it?
enum Ownership {
  /// Seen and saved, not owned. Someone recommended it, or it came off a clip.
  /// This is the state the judged tie-break criterion is about.
  ///
  /// Tree word is 'Bud', not 'Seed'. Changed 2026-09-26: a seed does not become
  /// an apple on a tree that already exists, it grows its own tree, so a
  /// recommendation arriving on YOUR tree is a bud on it. The social act of
  /// taking a cutting from someone else's tree keeps the graft word. `name` is
  /// what persists, so this cost no migration.
  spotted('Want it', 'Bud'),
  owned('Own it', 'On the tree'),

  /// Sold, traded, refunded, or lapsed out of a subscription.
  released('Gave it away', 'Given away');

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

/// Where a share came from.
///
/// Deliberately NOT named SourcePlatform: `Platform` above means a console a
/// copy lives on, and one word meaning two things in one file is how a later
/// edit puts a YouTube link on a branch.
///
/// `text` is the case with no link at all, which is a normal share and not a
/// failure: a friend typing "play Hollow Knight" is the app's whole premise.
enum SourceKind {
  youtube('YouTube'),
  twitch('Twitch'),
  tiktok('TikTok'),
  instagram('Instagram'),
  x('X'),
  reddit('Reddit'),
  steam('Steam'),

  /// Any other page that served readable metadata. Blogs, news, forums.
  web('Web'),

  /// Shared text carrying no usable link.
  text('Shared text');

  const SourceKind(this.label);
  final String label;
}

/// How a share was turned into a game, strongest first.
///
/// Stored per source because it decides how much to trust the row later, and
/// because it is the only way to tell which resolver tier is actually earning
/// its place once real shares start arriving.
enum MatchMethod {
  /// An id came back, so nothing was guessed. A Twitch clip carries the game
  /// id outright; a Steam link carries an appid.
  exact('Exact match'),

  /// Matched on title, description or tags from the page's own metadata.
  metadata('From the page details'),

  /// Matched on shared prose. The weakest automatic tier, and the only one
  /// where a common English word can masquerade as a title.
  text('From the text'),

  /// The user picked it. Beats every automatic tier by definition.
  manual('You chose it');

  const MatchMethod(this.label);
  final String label;
}
