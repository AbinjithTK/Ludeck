import 'package:flutter/material.dart';

import '../../services/entitlement_service.dart';
import '../tokens.dart';

/// One purchasable plan.
///
/// Product ids are frozen in DECISIONS.md and must not be re-decided here.
/// Prices are display strings on purpose: the real localised price comes from
/// the store, and hardcoding a formatted number is how a paywall ends up
/// showing dollars to someone being charged rupees. These are the fallback for
/// before the store is connected, and a comment rather than a lie about it.
class Plan {
  const Plan({
    required this.productId,
    required this.title,
    required this.price,
    required this.note,
    this.trialDays,
  });

  final String productId;
  final String title;
  final String price;
  final String note;
  final int? trialDays;

  static const annual = Plan(
    productId: 'pro_annual',
    title: 'Yearly',
    price: '\$19.99',
    note: 'Works out cheapest',
    trialDays: 30,
  );

  static const monthly = Plan(
    productId: 'pro_monthly',
    title: 'Monthly',
    price: '\$2.99',
    note: 'Cancel whenever',
  );

  static const lifetime = Plan(
    productId: 'pro_lifetime',
    title: 'Once',
    price: '\$39.99',
    note: 'Paid once, yours for good',
  );

  /// Annual first because it carries the trial, which is also what the Devpost
  /// rules require so judges can reach the paid features without a promo code.
  static const all = [annual, monthly, lifetime];
}

/// What paying actually buys.
///
/// The hard rule from DECISIONS.md: collection size and sharing are NEVER
/// gated. So this screen must not imply they are. It sells the insight layer and
/// says so plainly, because a paywall that hints your games are capped when they
/// are not is worse than no paywall: the user finds out it was untrue, and then
/// nothing else the app says is trustworthy either.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.service});

  final EntitlementService service;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Plan _selected = Plan.annual;
  bool _busy = false;
  String? _error;

  /// The store's real prices and trials once they arrive. Until then (and on
  /// a build with no store) the Plan fallbacks show.
  Map<String, StoreOffer> _offers = const {};

  @override
  void initState() {
    super.initState();
    widget.service.offers().then((o) {
      if (mounted && o.isNotEmpty) setState(() => _offers = o);
    }, onError: (Object _) {});
  }

  String _priceOf(Plan p) => _offers[p.productId]?.price ?? p.price;

  /// The store's answer wins once it is known: a trial is only promised when
  /// the store says the plan has one.
  int? _trialOf(Plan p) =>
      _offers.containsKey(p.productId) ? _offers[p.productId]!.trialDays : p.trialDays;

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entitled = await widget.service.purchase(_selected.productId);
      if (!mounted) return;
      if (entitled) {
        Navigator.of(context).pop(true);
        return;
      }
      // Cancelled. Not an error, so nothing is said about it: the user knows
      // they just backed out and telling them so reads as nagging.
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That did not go through. Nothing has been charged.';
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.restore();
      if (!mounted) return;
      if (widget.service.isPro) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        _error = 'No earlier purchase found on this account.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not check. Try again in a moment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: Tokens.palette.textDim),
                  // Always available, never delayed. A close button that
                  // appears after a countdown is a dark pattern.
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  tooltip: 'Close',
                ),
              ),

              // Scrolls rather than using a Spacer. The first version used one
              // and overflowed: this content does not fit an 800 by 600 surface,
              // and it would equally not fit a short phone in landscape or
              // anyone using a large accessibility text size. A paywall that
              // overflows is a paywall nobody can complete.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('See more in your collection',
                          style: text.displaySmall),
                      SizedBox(height: Tokens.space.sm),
                      Text(
                        'Your games, your branches and sharing your tree are '
                        'free, and always will be. Paying adds the reading of '
                        'it.',
                        style: TextStyle(
                          fontSize: Tokens.type.body,
                          height: Tokens.type.leadingBody,
                          color: Tokens.palette.textDim,
                        ),
                      ),
                      SizedBox(height: Tokens.space.md),
                      _benefit('What to play tonight, narrowed by the time you '
                          'actually have and the console within reach'),
                      _benefit('How a season went, finished and set aside '
                          'side by side'),
                      _benefit('What you have spent, per platform'),
                      _benefit('How long the rest of the collection would take'),
                      SizedBox(height: Tokens.space.lg),
                      for (final plan in Plan.all) _planRow(plan),
                      if (_error != null) ...[
                        SizedBox(height: Tokens.space.sm),
                        Text(
                          _error!,
                          style: TextStyle(
                            fontSize: Tokens.type.caption,
                            color: Tokens.palette.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: Tokens.space.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _buy,
                  style: FilledButton.styleFrom(
                    backgroundColor: Tokens.palette.accent,
                    foregroundColor: Tokens.palette.bg,
                    padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
                  ),
                  child: Text(
                    _trialOf(_selected) == null
                        ? 'Continue'
                        : 'Start ${_trialOf(_selected)} days free',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(height: Tokens.space.xs),
              Center(
                child: TextButton(
                  // Reachable without buying anything, which is the point:
                  // somebody who already paid on another device has to be able
                  // to get back in.
                  onPressed: _busy ? null : _restore,
                  child: Text(
                    'Already paid? Restore',
                    style: TextStyle(
                      fontSize: Tokens.type.caption,
                      color: Tokens.palette.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefit(String label) => Padding(
        padding: EdgeInsets.only(bottom: Tokens.space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: Tokens.space.xxs),
              child: Icon(Icons.circle,
                  size: 5, color: Tokens.palette.accent),
            ),
            SizedBox(width: Tokens.space.xs),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: Tokens.type.body,
                  height: Tokens.type.leadingBody,
                  color: Tokens.palette.text,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _planRow(Plan plan) {
    final selected = plan.productId == _selected.productId;
    return Padding(
      padding: EdgeInsets.only(bottom: Tokens.space.xs),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radius.card),
          onTap: _busy ? null : () => setState(() => _selected = plan),
          child: Container(
            padding: EdgeInsets.all(Tokens.space.sm),
            decoration: BoxDecoration(
              color: Tokens.palette.surface,
              borderRadius: BorderRadius.circular(Tokens.radius.card),
              border: Border.all(
                // Selection is carried by border colour AND the filled radio
                // mark, never by colour alone.
                color: selected ? Tokens.palette.accent : Tokens.palette.surface,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color:
                      selected ? Tokens.palette.accent : Tokens.palette.textDim,
                ),
                SizedBox(width: Tokens.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        style: TextStyle(
                          fontSize: Tokens.type.body,
                          color: Tokens.palette.text,
                        ),
                      ),
                      Text(
                        plan.note,
                        style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: Tokens.palette.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _priceOf(plan),
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    fontWeight: FontWeight.w600,
                    color: Tokens.palette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
