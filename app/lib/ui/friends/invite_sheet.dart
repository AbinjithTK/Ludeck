// Invite a friend: your link as a QR code to scan across a table, plus the
// link and your ID to paste into a chat.
//
// The link is the public web page for your orchard (tree_links.dart), so it
// works for someone who does not have Ludeck yet: the page shows your tree
// and offers "Open in Ludeck". The QR code carries exactly that link.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/social/social_backend.dart';
import '../../services/social/tree_links.dart';
import '../account/account_widgets.dart';
import '../tokens.dart';

Future<void> showInviteSheet(BuildContext context, SocialProfile me) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _InviteSheet(me: me),
    );

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.me});

  final SocialProfile me;

  Future<void> _copy(BuildContext context, String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final link = treeLinkFor(me.handle);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.lg, 0, Tokens.space.lg, Tokens.space.lg),
        child: Column(
          key: const Key('invite-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountTitle('Invite a friend',
                body: me.isPrivate
                    ? 'They can find you as @${me.handle}. Your orchard is '
                        'friends only, so they will ask to follow and you say '
                        'yes.'
                    : 'They can find you as @${me.handle}, or scan this to '
                        'open your orchard.'),
            SizedBox(height: Tokens.space.md),
            Center(
              child: Semantics(
                label: 'QR code for your orchard link',
                image: true,
                child: Container(
                  padding: EdgeInsets.all(Tokens.space.sm),
                  decoration: BoxDecoration(
                    // Dark modules on a light ground: what every camera app
                    // reads most reliably.
                    color: Tokens.palette.text,
                    borderRadius: BorderRadius.circular(Tokens.radius.card),
                  ),
                  child: QrImageView(
                    key: const Key('invite-qr'),
                    data: link,
                    size: 200,
                    backgroundColor: Tokens.palette.text,
                    eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Tokens.palette.bg),
                    dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Tokens.palette.bg),
                  ),
                ),
              ),
            ),
            SizedBox(height: Tokens.space.sm),
            SelectableText(link,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Tokens.palette.textDim,
                    fontSize: Tokens.type.caption)),
            SizedBox(height: Tokens.space.md),
            FilledButton.icon(
              key: const Key('invite-copy-link'),
              onPressed: () => _copy(context,
                  'Come see my orchard on Ludeck: $link', 'Link copied.'),
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.palette.accent,
                foregroundColor: Tokens.palette.bg,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Copy invite link'),
            ),
            SizedBox(height: Tokens.space.xs),
            OutlinedButton.icon(
              key: const Key('invite-copy-id'),
              onPressed: () => _copy(context,
                  'Find me on Ludeck: @${me.handle}', 'ID copied.'),
              icon: const Icon(Icons.alternate_email_rounded),
              label: Text('Copy my ID, @${me.handle}'),
            ),
          ],
        ),
      ),
    );
  }
}
