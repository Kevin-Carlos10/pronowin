import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';

/// Les pages légales publiées sur le site.
///
/// Le paywall y renvoie plutôt que d'ouvrir la copie embarquée. C'est la
/// version publique : celle que l'on cite, celle qu'un examinateur ouvre, et
/// la seule qu'un utilisateur puisse lire sans avoir l'application sous la
/// main — au moment de décider s'il paie.
///
/// ── Le canal fait partie de l'adresse ──────────────────────────────────────
///
/// Le texte des conditions générales diffère selon le canal, et pas par
/// commodité : la version des boutiques ne publie pas l'article décrivant
/// l'activation Premium contre l'ouverture d'un compte chez le bookmaker
/// partenaire. Cet article décrit une offre qui n'existe pas dans ce build, et
/// c'est précisément celui qui ferait classer l'application dans une catégorie
/// réservée aux organisations.
///
/// Envoyer un build store vers l'adresse du canal direct publierait donc, sous
/// notre propre lien, exactement ce que ce build a retiré. Le site sert la
/// version des boutiques par défaut ; la variante directe se demande.
///
/// Regroupé ici pour la même raison que `BookmakerAffiliation.ouvrir` : six
/// liens, dans trois écrans, mènent à ces pages. Six copies de la même adresse
/// et du même geste d'ouverture divergeraient — c'est d'ailleurs ce qui était
/// arrivé, avec trois comportements différents pour trois liens qui font la
/// même chose.
class PagesLegales {
  /// Conditions générales d'utilisation, pour le canal donné.
  static String cgu({required bool estStore}) => estStore
      ? '${AppConstants.siteUrl}/cgu'
      : '${AppConstants.siteUrl}/cgu?canal=direct';

  /// Mentions légales — elles vivent sur le site, et nulle part ailleurs.
  ///
  /// Elles portent l'identité de l'éditeur. La recopier dans
  /// l'application créerait un second endroit où ce nom et cette adresse
  /// devraient rester à jour, et l'un des deux finirait par mentir.
  static String get mentionsLegales =>
      '${AppConstants.siteUrl}/mentions-legales';

  /// Politique de confidentialité — l'URL déclarée à Google Play.
  static String get confidentialite => '${AppConstants.siteUrl}/confidentialite';

  /// Ouvre une page légale dans le navigateur du système.
  ///
  /// ── Ce que la webview interne faisait à la place ──────────────────────────
  ///
  /// Ces liens passaient par `/navigateur`, une webview affichant la page sans
  /// quitter l'application. L'argument était le paywall : envoyer quelqu'un
  /// dans Chrome au moment où il décide de payer, c'est le perdre.
  ///
  /// Ce que cet arbitrage n'avait pas vu, c'est ce que la webview montre
  /// réellement. Les pages du site portent leur propre en-tête, avec le logo
  /// et « Retour à l'accueil ». Empilé sous la barre de l'application, cela
  /// donnait deux en-têtes — et surtout une sortie : la toucher chargeait la
  /// page d'accueil commerciale *dans* l'application, dont l'appel à l'action
  /// est « Télécharger l'app ». On proposait de télécharger l'application
  /// depuis l'intérieur de l'application.
  ///
  /// Le navigateur du système n'a pas ce défaut : la page s'ouvre chez elle,
  /// avec son en-tête à sa place, et revenir se fait par le geste système que
  /// tout le monde connaît.
  ///
  /// ── L'échec doit rester visible ───────────────────────────────────────────
  ///
  /// C'est la contrepartie de sortir de l'application, et la seule chose qui
  /// pouvait mal tourner dans cette bascule. Un lien légal qui ne fait rien
  /// quand on le touche est un défaut que ce projet a déjà corrigé deux fois.
  ///
  /// Deux précautions, donc :
  ///
  ///  - **pas de `canLaunchUrl`.** Sur Android il répond faux dès qu'aucune
  ///    requête de visibilité de paquet ne couvre le schéma, alors même que
  ///    l'ouverture aurait réussi. S'y fier transformerait un lien qui marche
  ///    en lien mort. On tente, et on ne retient l'échec que s'il se produit.
  ///  - **un échec dit à l'écran.** `launchUrl` peut aussi renvoyer `false`
  ///    sans lever. Dans les deux cas l'utilisateur voit l'adresse et peut la
  ///    copier : il reste un chemin vers le texte légal, ce qui est
  ///    précisément ce qu'on doit lui garantir.
  static Future<void> ouvrir(BuildContext context, String url,
      {String titre = ''}) async {
    HapticFeedback.selectionClick();

    // Capturé avant le premier `await` : `context` ne survit pas forcément à
    // la coupure, le messager si.
    final messager = ScaffoldMessenger.maybeOf(context);

    var ouverte = false;
    try {
      ouverte = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Légal] ouverture de $url impossible : $e');
    }
    if (ouverte) return;

    debugPrint('[Légal] aucun navigateur n\'a pris $url');
    messager?.showSnackBar(SnackBar(
      content: Text(
        titre.isEmpty
            ? 'Impossible d\'ouvrir le navigateur.\n$url'
            : 'Impossible d\'ouvrir « $titre ».\n$url',
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Copier',
        onPressed: () => Clipboard.setData(ClipboardData(text: url)),
      ),
    ));
  }

  /// Le titre de la barre, pour chaque page.
  static const String titreCgu = 'Conditions d\'utilisation';
  static const String titreConfidentialite = 'Politique de confidentialité';
}
