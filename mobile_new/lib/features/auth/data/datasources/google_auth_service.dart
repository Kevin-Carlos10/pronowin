import 'package:flutter/foundation.dart';
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

  /// Le `--dart-define` n'est **pas** obligatoire sur Android.
  ///
  /// Quand `serverClientId` vaut `null`, le plugin lit lui-même la ressource
  /// `default_web_client_id` que le greffon Gradle génère depuis
  /// `google-services.json` :
  ///
  ///     _serverClientId = params.serverClientId
  ///         ?? await _hostApi.getGoogleServicesJsonServerClientId();
  ///
  /// Le passer explicitement ne sert donc qu'à forcer une autre valeur que
  /// celle du fichier — utile pour viser un projet Google différent de celui
  /// de Firebase, inutile ici. Sur iOS, c'est `GoogleService-Info.plist` qui
  /// joue le même rôle.
  ///
  /// Conséquence : le bouton Google reste offert dans tous les cas. Une
  /// version antérieure de ce fichier le masquait quand le `--dart-define`
  /// manquait — ce qui aurait privé les utilisateurs d'un chemin parfaitement
  /// fonctionnel.
  static bool get aIdentifiantExplicite => _serverClientId.isNotEmpty;

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
    // Le contexte est journalisé avant la tentative, pas seulement en cas
    // d'échec : quand rien ne s'affiche ensuite, savoir avec quoi on est parti
    // vaut mieux que de le déduire.
    debugPrint('[Google] identifiant explicite : '
        '${_serverClientId.isEmpty
            ? "aucun — le plugin lira default_web_client_id de google-services.json"
            : _serverClientId}');

    try {
      await _ensureInitialise();
    } catch (e) {
      debugPrint('[Google] initialize() a échoué : $e');
      rethrow;
    }

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      debugPrint('[Google] supportsAuthenticate() = false');
      throw Exception('Connexion Google indisponible sur cet appareil.');
    }

    final GoogleSignInAccount compte;
    try {
      compte = await GoogleSignIn.instance.authenticate();
      debugPrint('[Google] compte obtenu : ${compte.email}');
    } on GoogleSignInException catch (e) {
      // Les détails sont journalisés AVANT le tri par code. La version
      // précédente sortait sur `canceled` en n'écrivant qu'« annulé par
      // l'utilisateur » — or c'est précisément là que se trouve le message
      // natif d'Android, et une annulation apparente peut aussi être un rejet
      // système : Credential Manager referme sa fenêtre et lève
      // `GetCredentialCancellationException` sans que personne ait touché
      // l'écran.
      debugPrint('[Google] code=${e.code.name}');
      debugPrint('[Google] description : ${e.description}');
      debugPrint('[Google] détails : ${e.details}');

      if (e.code == GoogleSignInExceptionCode.canceled) {
        // `canceled` recouvre deux situations opposées, que le SDK ne
        // distingue pas : l'utilisateur qui referme la fenêtre, et Google qui
        // refuse le compte. Dans le second cas, se taire laisse l'utilisateur
        // devant un bouton qui ne fait rien.
        if (estRejetSysteme(e.description)) {
          throw Exception(messageRejetSysteme(e.description));
        }
        return null;
      }
      throw Exception(messageErreurGoogle(e));
    } catch (e, pile) {
      // Le filet manquant : `authenticate()` peut remonter autre chose qu'une
      // `GoogleSignInException` — une `PlatformException` du canal natif, par
      // exemple. Ces cas-là ne laissaient aucune trace, et l'échec restait
      // aussi muet qu'avant l'ajout des journaux.
      debugPrint('[Google] exception inattendue (${e.runtimeType}) : $e');
      debugPrint('[Google] $pile');
      throw Exception(
          'La connexion Google a échoué. Utilise ton adresse e-mail en '
          'attendant.');
    }

    final idToken = compte.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      // Cas typique d'une configuration incomplète : sans serverClientId, la
      // plateforme renvoie un compte mais aucun jeton d'identité.
      debugPrint('[Google] compte reçu mais AUCUN idToken — '
          'serverClientId absent ou non reconnu par Google');
      throw Exception(
          'Google n\'a pas fourni de jeton d\'identité. '
          'Vérifie la configuration OAuth du projet.');
    }
    debugPrint('[Google] idToken reçu (${idToken.length} caractères)');
    return idToken;
  }

  static Future<void> deconnecter() async {
    if (!_initialise) return;
    await GoogleSignIn.instance.signOut();
  }
}

/// Une « annulation » qui n'en est pas une.
///
/// Le SDK renvoie `canceled` aussi bien quand l'utilisateur referme la fenêtre
/// que lorsque les services Google Play refusent le compte. Dans le second cas,
/// la description porte un code de statut entre crochets :
///
///     [16] Account reauth failed.
///
/// Ce format `[nombre]` vient des services Google Play et n'apparaît jamais sur
/// une fermeture volontaire — c'est ce qui permet de les séparer. Le repère est
/// modeste, et il ne coûte rien s'il se trompe : au pire, un utilisateur qui a
/// vraiment annulé voit un message qu'il peut ignorer. L'inverse — se taire
/// alors que Google a refusé — laisse quelqu'un devant un bouton mort.
bool estRejetSysteme(String? description) =>
    description != null && RegExp(r'^\s*\[\d+\]').hasMatch(description);

/// Message pour un compte refusé par les services Google de l'appareil.
String messageRejetSysteme(String? description) {
  final d = description ?? '';

  // Le cas rencontré en pratique, et le seul dont la solution soit précise.
  if (d.toLowerCase().contains('reauth')) {
    return 'Ton compte Google doit être reconnecté sur cet appareil. '
           'Ouvre les réglages Android → Comptes, reconnecte-toi, puis '
           'réessaie. Tu peux aussi utiliser ton adresse e-mail.';
  }

  return 'Les services Google de cet appareil ont refusé la connexion. '
         'Utilise ton adresse e-mail, ou réessaie plus tard.';
}

/// Traduit un échec Google en phrase utile — à l'utilisateur, et à celui qui
/// devra corriger la configuration.
///
/// Trois de ces codes ne sont pas des incidents d'usage mais des défauts de
/// paramétrage : ils ne se résolvent pas en réessayant, et le dire évite à
/// l'utilisateur de s'acharner comme au support d'enquêter à l'aveugle.
String messageErreurGoogle(GoogleSignInException e) {
  switch (e.code) {
    case GoogleSignInExceptionCode.canceled:
      return 'Connexion annulée.';

    case GoogleSignInExceptionCode.interrupted:
      return 'La connexion a été interrompue. Réessaie.';

    case GoogleSignInExceptionCode.clientConfigurationError:
      // Typiquement : empreinte SHA-1 absente de la console Google, ou
      // enregistrée sur une autre application que celle installée.
      return 'La connexion Google n\'est pas correctement configurée pour '
             'cette version de l\'app. Utilise ton adresse e-mail en attendant.';

    case GoogleSignInExceptionCode.providerConfigurationError:
      // Côté Google : services Play absents ou trop anciens, fournisseur
      // indisponible sur cet appareil.
      return 'Les services Google de cet appareil ne permettent pas la '
             'connexion. Mets à jour les services Google Play, ou utilise ton '
             'adresse e-mail.';

    case GoogleSignInExceptionCode.uiUnavailable:
      // Aucun compte Google sur l'appareil, ou l'interface système ne peut pas
      // s'afficher.
      return 'Aucun compte Google disponible sur cet appareil. '
             'Ajoute-en un dans les réglages, ou utilise ton adresse e-mail.';

    case GoogleSignInExceptionCode.userMismatch:
      return 'Le compte choisi ne correspond pas à celui attendu.';

    case GoogleSignInExceptionCode.unknownError:
      return 'La connexion Google a échoué. Utilise ton adresse e-mail en '
             'attendant.';
  }
}
