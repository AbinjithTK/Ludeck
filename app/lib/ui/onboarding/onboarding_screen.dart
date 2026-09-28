// First-run onboarding: the direct answer to this project's own critique
// finding that "nothing on screen teaches the interaction" -- press-and-hold
// to move a game between branches, tap for status, and sharing were all
// invisible before this existed.
//
// Shown once (persisted via shared_preferences, already a resolved transitive
// dependency of supabase_flutter -- no new package needed), skippable at every
// step, and re-openable from the profile screen at any time. Nothing here
// teaches by demonstration on real data: every screen is static copy plus the
// same primitives (SoftCard, GlowOrb) the real screens use, so onboarding
// cannot show an interaction that has since changed shape without the same
// widgets changing under it.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../gamified/primitives.dart';
import '../tokens.dart';

const _seenKey = 'onboarding_seen_v1';

/// Whether onboarding has been shown before. Checked once at startup to decide
/// whether to route straight to it.
Future<bool> hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_seenKey) ?? false;
}

Future<void> _markSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_seenKey, true);
}

class _Page {
  const _Page({required this.title, required this.body, required this.icon});
  final String title;
  final String body;
  final IconData icon;
}

const _pages = [
  _Page(
    icon: Icons.park_outlined,
    title: 'Your games, as an orchard',
    body: 'Every game you own or want to play hangs on a tree as a cover. '
        'Finished games glow gold. That is the only thing this app marks. '
        "Nothing is ever shown as locked, overdue, or behind.",
  ),
  _Page(
    icon: Icons.call_split,
    title: 'Trees are yours to name',
    body: 'Group games however makes sense to you: "Cozy", "Co-op with '
        'Dev", "Bought in a sale, no regrets". Trees are not genres or '
        'platforms. They are your own categories.',
  ),
  _Page(
    icon: Icons.touch_app_outlined,
    title: 'Swipe, tap, hold',
    body: 'Swipe between trees. Tap a cover to open that game. Press and '
        'hold a cover, then drop it on another tree\'s dot to move it there.',
  ),
  _Page(
    icon: Icons.ios_share,
    title: 'Share your tree, or visit someone else\'s',
    body: 'Publish your tree to get a link. It is private by default, and only '
        'title, cover, status and rating are ever shared, never your notes '
        'or who recommended a game. Visit a friend\'s tree to see their '
        'branches and plant anything that catches your eye.',
  ),
];

/// The onboarding route itself: a swipeable sequence ending in "Get started".
/// Skippable from any page.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onDone});

  /// Called after the user finishes or skips. Defaults to popping the route,
  /// which is right for the "re-open from profile" case; the first-run case
  /// passes a replacement instead, since there is nothing to pop back to.
  final VoidCallback? onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  Future<void> _finish() async {
    await _markSeen();
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: Tokens.palette.bg,
      body: CosmosBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(Tokens.space.sm),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Skip',
                      style: TextStyle(color: Tokens.palette.textDim),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _OnboardingPage(page: _pages[i]),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(Tokens.space.lg),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: Tokens.space.xxs),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _page
                                    ? Tokens.palette.accent
                                    : Tokens.cosmos.panelEdge,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: Tokens.space.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isLast
                            ? _finish
                            : () => _controller.nextPage(
                                  duration: Tokens.motion.grow,
                                  curve: Curves.easeOut,
                                ),
                        child: Text(isLast ? 'Get started' : 'Next'),
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        // Centering intent, without depending on the content ever fitting a
        // guessed height -- a large text-scale setting made this overflow a
        // fixed-height PageView page under the test font, the same class of
        // trap this project's lessons already document. A ConstrainedBox
        // with the viewport's own minHeight keeps short copy centred while
        // letting long copy simply scroll.
        padding: EdgeInsets.all(Tokens.space.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlowOrb(
                diameter: 88,
                glow: 0.6,
                child: Icon(page.icon, size: 36, color: Tokens.palette.text),
              ),
              SizedBox(height: Tokens.space.lg),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Tokens.type.displayFamily,
                  fontSize: Tokens.type.title,
                  fontWeight: FontWeight.w700,
                  color: Tokens.palette.text,
                ),
              ),
              SizedBox(height: Tokens.space.sm),
              Text(
                page.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Tokens.type.body,
                  color: Tokens.palette.textDim,
                ),
              ),
            ],
          ),
        ),
      );
}
