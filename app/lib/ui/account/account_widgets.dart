// Small pieces the account, setup and password screens share, so the three
// read as one flow: the same field, the same title, the same orb.

import 'package:flutter/material.dart';

import '../../services/social/social_backend.dart';
import '../tokens.dart';

/// The text field look used across the app (see friends_screen.dart).
InputDecoration accountField({
  required String hint,
  String? prefix,
  String? error,
  String? helper,
  Widget? suffix,
}) =>
    InputDecoration(
      prefixText: prefix,
      prefixStyle: TextStyle(color: Tokens.palette.textDim),
      hintText: hint,
      hintStyle: TextStyle(color: Tokens.palette.textDim),
      errorText: error,
      helperText: helper,
      helperStyle: TextStyle(color: Tokens.palette.textDim),
      suffixIcon: suffix,
      filled: true,
      fillColor: Tokens.cosmos.panelDeep,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        borderSide: BorderSide(color: Tokens.cosmos.panelEdge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        borderSide: BorderSide(color: Tokens.palette.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        borderSide: BorderSide(color: Tokens.palette.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        borderSide: BorderSide(color: Tokens.palette.danger),
      ),
    );

class AccountTitle extends StatelessWidget {
  const AccountTitle(this.title, {super.key, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: Tokens.type.displayFamily,
              fontSize: Tokens.type.title,
              letterSpacing: Tokens.type.trackingTitle,
              fontWeight: FontWeight.w700,
              color: Tokens.palette.text,
            ),
          ),
          if (body != null) ...[
            SizedBox(height: Tokens.space.xs),
            Text(
              body!,
              style: TextStyle(
                fontSize: Tokens.type.body,
                height: Tokens.type.leadingBody,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ],
      );
}

/// A person's orb, lit in the colours of the tree skin they picked. The tree
/// is the avatar: no photo, just their initial on their tree's light.
class ProfileOrb extends StatelessWidget {
  const ProfileOrb({
    super.key,
    required this.seed,
    required this.name,
    this.diameter = 44,
    this.selected = false,
  });

  final String? seed;
  final String name;
  final double diameter;

  /// Draws a gold ring. Used by the avatar picker only.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final skin = Tokens.skins.named(seed);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [skin.foliageLit, skin.foliageNear, skin.foliageFar],
          stops: const [0, 0.55, 1],
        ),
        border: Border.all(
          color: selected ? Tokens.palette.accent : Tokens.cosmos.panelEdge,
          width: selected ? 3 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: Tokens.type.displayFamily,
          fontSize: diameter * 0.42,
          fontWeight: FontWeight.w700,
          color: Tokens.palette.text,
          shadows: [Shadow(color: Tokens.cosmos.captionShadow, blurRadius: 4)],
        ),
      ),
    );
  }
}

/// Plain words for an account failure, for the screen to show.
String accountFailureText(SocialException e) => switch (e.failure) {
      SocialFailure.offline => "Couldn't reach the network. Check your connection.",
      SocialFailure.unauthorized => e.detail == 'credentials' ||
              e.detail == 'invalid_credentials'
          ? "That email and password don't match."
          // A sentence from the auth stream ('Google sign-in took too long.')
          // is already written for people; a code is not.
          : (e.detail?.endsWith('.') ?? false)
              ? e.detail!
              : "Sign-in didn't finish. Try again.",
      SocialFailure.emailNotConfirmed =>
        'Open the link we emailed you first, then sign in.',
      SocialFailure.conflict =>
        'That email already has an account. Sign in instead.',
      SocialFailure.invalid => e.detail == 'weak password' ||
              e.detail == 'weak_password'
          ? 'Use at least 6 characters for your password.'
          : 'Check the email address and try again.',
      SocialFailure.rateLimited =>
        'Too many tries just now. Wait a minute and try again.',
      SocialFailure.forbidden =>
        "This email can't sign up here yet. Try Google instead.",
      SocialFailure.notConfigured =>
        "Accounts aren't set up on this build. Everything still works on this phone.",
      SocialFailure.malformed ||
      SocialFailure.notFound =>
        'Something went wrong on our side. Try again.',
    };
