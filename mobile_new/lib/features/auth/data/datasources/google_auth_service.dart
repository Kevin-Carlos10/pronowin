import 'package:google_sign_in/google_sign_in.dart';

/// Connexion Google — côté client uniquement.
///
/// Ce service ne fait qu'obtenir un `idToken` signé par Google. **Il ne crée
/// aucune session** : le jeton part au backend, qui vérifie sa signature, son
/// audience et son expiration avant d'ouvrir quoi que ce soit. Un jeton obtenu
/// ici n'a aucune valeur d'authentification tant que le serveur ne l'a pas
/// validé.
class GoogleAuthService {
  static bool _initialise = false;

  /// `serverClientId` doit être l'identifiant OAuth **Web** du projet Google,
  /// le même que celui listé dans `GOOGLE_CLIENT_IDS` côté serveur : c'est lui
  /// qui devient l'audience du jeton, et donc ce que le backend vérifie.
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static Future<void> _ensureInitialise() async {
    if (_initialise) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialise = true;
  }

  /// Lance le sélecteur de compte Google.
  ///
  /// Retourne `null` si l'utilisateur annule — ce n'est pas une erreur et ça ne
  /// doit pas remonter comme telle à l'écran.
  static Future<String?> obtenirIdToken() async {
    await _ensureInitialise();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw Exception(
          'Connexion Google indisponible sur cet appareil.');
    }

    final GoogleSignInAccount compte;
    try {
      compte = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = compte.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      // Cas typique d'une configuration incomplète : sans serverClientId, la
      // plateforme renvoie un compte mais aucun jeton d'identité.
      throw Exception(
          'Google n\'a pas fourni de jeton d\'identité. '
          'Vérifie la configuration OAuth du projet.');
    }
    return idToken;
  }

  static Future<void> deconnecter() async {
    if (!_initialise) return;
    await GoogleSignIn.instance.signOut();
  }
}
