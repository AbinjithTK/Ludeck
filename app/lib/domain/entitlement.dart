/// What a free user can and cannot do. Pure logic, no SDK import, so the rules
/// can be tested with no store connection and no RevenueCat account.
///
/// `EntitlementService` (still to be built) wraps the real purchase state and
/// delegates the actual free/paid decision to this file. No screen should ever
/// ask the purchase SDK a yes/no question directly; it asks this file, through
/// that service.
enum Capability {
  /// What to play tonight, filtered by time available, device, or mood.
  reasonedPick,

  /// The season rollup screen: harvested, pressed, still growing, seeds.
  seasonSummary,

  /// What was spent, broken down per platform.
  spendAnalysis,

  /// A projection of how long the remaining collection would take to clear.
  timeToClear,
}

/// True when a free user may use this capability. Everything NOT listed here
/// is free, which is the point: the default is free, and paid status is
/// something a capability has to be explicitly given, not something the
/// absence of a rule falls back to.
///
/// Two things are deliberately never gated anywhere in this file, and there is
/// no `Capability` value for either: collection size, and sharing. QuestLog
/// gates at 15 games and Cibby at 10, and both are worse products for it. A
/// free `choosePick` with no filters answering the core question the app
/// exists to answer must also never require payment; only the FILTERED,
/// reasoned version below is paid.
bool isFree(Capability c) => switch (c) {
      Capability.reasonedPick => false,
      Capability.seasonSummary => false,
      Capability.spendAnalysis => false,
      Capability.timeToClear => false,
    };

/// The actual gate a screen calls. `isPro` comes from `EntitlementService`,
/// which is the only file wrapping the purchase SDK; this function itself
/// never asks a store for anything.
bool allows(Capability c, {required bool isPro}) => isPro || isFree(c);
