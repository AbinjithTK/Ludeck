// The single door off the orchard.
//
// The header used to carry three glass circles (Library, Friends, You) laid
// over the sky. They read as a toolbar on the scene and, at a glance, Friends
// (two outlines) and You (one) were the same shape. This replaces all three
// with one Settings gear, and the places they went to live here as plain rows
// instead. Nothing is lost: every destination the header reached is one tap
// deeper, and the meadow is no longer covered by chrome.
//
// Presentational: each destination is a callback so a test can mount the
// screen with no navigator wiring. main.dart supplies them.

import 'package:flutter/material.dart';

import '../gamified/primitives.dart';
import '../tokens.dart';

/// One place Settings can take you.
typedef SettingsDestination = ({
  IconData icon,
  String title,
  String subtitle,
  VoidCallback onTap,
});

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onLibrary,
    required this.onFriends,
    required this.onProfile,
    this.onAccount,
    this.accountSubtitle,
    this.onLately,
    this.onInbox,
    this.unreadInbox,
  });

  /// What friends planted, finished and rated lately.
  final VoidCallback? onLately;

  /// Seeds sent to you, and follows and hypes.
  final VoidCallback? onInbox;

  /// How many inbox items are new. Shown to you only, on this row.
  final Future<int> Function()? unreadInbox;

  /// Sign in, or edit your profile once signed in. Optional so a test can
  /// mount the screen without accounts.
  final VoidCallback? onAccount;

  /// Read at build time, so the row says who is signed in right now.
  final String Function()? accountSubtitle;

  /// Your whole collection: owned games and wishlist.
  final VoidCallback onLibrary;

  /// Open someone's tree by their handle.
  final VoidCallback onFriends;

  /// Your orchard, level and share card.
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final destinations = <SettingsDestination>[
      if (onAccount != null)
        (
          icon: Icons.account_circle_outlined,
          title: 'Account',
          subtitle: accountSubtitle?.call() ?? 'Sign in or create an account',
          onTap: onAccount!,
        ),
      (
        icon: Icons.person_rounded,
        title: 'You',
        subtitle: 'Your orchard, level and share card',
        onTap: onProfile,
      ),
      (
        icon: Icons.grid_view_rounded,
        title: 'Library',
        subtitle: 'Every game you track',
        onTap: onLibrary,
      ),
      (
        icon: Icons.group_outlined,
        title: 'Friends',
        subtitle: "Open someone's tree by their handle",
        onTap: onFriends,
      ),
      if (onLately != null)
        (
          icon: Icons.local_florist_outlined,
          title: 'Lately',
          subtitle: 'What friends planted, finished and rated',
          onTap: onLately!,
        ),
    ];

    return Scaffold(
      body: CosmosBackdrop(
        sky: Sky.deep,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(Tokens.space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (Navigator.of(context).canPop())
                    BackButton(color: Tokens.palette.text),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontFamily: Tokens.type.displayFamily,
                      fontSize: Tokens.type.title,
                      letterSpacing: Tokens.type.trackingTitle,
                      color: Tokens.palette.text,
                    ),
                  ),
                ]),
                SizedBox(height: Tokens.space.md),
                for (final d in destinations) ...[
                  _SettingsRow(destination: d),
                  SizedBox(height: Tokens.space.sm),
                ],
                if (onInbox != null)
                  FutureBuilder<int>(
                    future: unreadInbox?.call() ?? Future.value(0),
                    builder: (context, snap) {
                      final n = snap.data ?? 0;
                      return _SettingsRow(
                        destination: (
                          icon: n > 0
                              ? Icons.mark_email_unread_outlined
                              : Icons.inbox_outlined,
                          title: 'Inbox',
                          subtitle: n == 0
                              ? 'Games friends send you, follows and hypes'
                              : '$n new',
                          onTap: onInbox!,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tappable row, the same card style as the profile's rows so the app
/// reads as one place and not a settings page bolted on.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.destination});

  final SettingsDestination destination;

  @override
  Widget build(BuildContext context) {
    final p = Tokens.palette;
    return Semantics(
      button: true,
      child: ListTile(
        key: Key('settings-${destination.title.toLowerCase()}'),
        contentPadding: EdgeInsets.symmetric(horizontal: Tokens.space.sm),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radius.card)),
        tileColor: p.surface,
        leading: Icon(destination.icon, color: p.accent),
        title: Text(destination.title,
            style: TextStyle(
                fontSize: Tokens.type.body,
                fontWeight: FontWeight.w600,
                color: p.text)),
        subtitle: Text(destination.subtitle,
            style: TextStyle(fontSize: Tokens.type.caption, color: p.textDim)),
        trailing: Icon(Icons.chevron_right_rounded, color: p.textDim),
        onTap: destination.onTap,
      ),
    );
  }
}
