import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Ce que « Se connecter avec Apple » rend au téléphone, à transmettre au
/// serveur — qui seul vérifie le jeton.
class IdentifiantsApple {
  final String identityToken;
  /// Le nonce brut : Apple a reçu son empreinte, le jeton la porte.
  final String nonce;
  final String? authorizationCode;
  /// Donnés par Apple à la toute première autorisation seulement.
  final String? givenName;
  final String? familyName;

  const IdentifiantsApple({
    required this.identityToken,
    required this.nonce,
    this.authorizationCode,
    this.givenName,
    this.familyName,
  });

  Map<String, dynamic> versApi() => {
    'identity_token': identityToken,
    'nonce': nonce,
    'authorization_code': ?authorizationCode,
    'given_name': ?givenName,
    'family_name': ?familyName,
  };
}

/// « Se connecter avec Apple » (règle 4.8 de l'App Store : exigé de toute app
/// qui propose une connexion tierce comme Google).
class AppleAuthService {
  AppleAuthService._();

  /// Sur iPhone seulement : Apple ne l'exige qu'à l'App Store, et sur Android
  /// il demanderait un service web dédié.
  static bool get disponible => defaultTargetPlatform == TargetPlatform.iOS;

  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';

  /// Un nonce neuf pour chaque tentative : il lie le jeton à cette demande,
  /// un jeton intercepté ne se rejoue pas.
  @visibleForTesting
  static String nonceBrut([Random? source]) {
    final r = source ?? Random.secure();
    return List.generate(32, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  /// Ce qu'Apple reçoit : l'empreinte SHA-256 du nonce, en hexadécimal.
  @visibleForTesting
  static String empreinte(String nonce) => sha256.convert(utf8.encode(nonce)).toString();

  /// `null` si la personne a fermé la fenêtre d'Apple : ce n'est pas une
  /// erreur, l'écran ne doit rien afficher.
  static Future<IdentifiantsApple?> obtenir() async {
    final nonce = nonceBrut();
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: empreinte(nonce),
      );
      final jeton = c.identityToken;
      if (jeton == null) throw Exception('Apple n\'a pas renvoyé d\'identité. Réessaie.');
      return IdentifiantsApple(
        identityToken: jeton,
        nonce: nonce,
        authorizationCode: c.authorizationCode,
        givenName: c.givenName,
        familyName: c.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      debugPrint('[Apple] ${e.code.name} : ${e.message}');
      throw Exception('La connexion Apple a échoué. Utilise ton adresse e-mail en attendant.');
    }
  }
}
