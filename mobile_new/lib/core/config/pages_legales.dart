import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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

  /// Ouvre une page légale dans la webview interne.
  ///
  /// La première version lançait le navigateur du système. C'était le mauvais
  /// choix, et l'écran des Paramètres le montrait déjà : « Mentions légales »
  /// y ouvrait `/navigateur`, une webview qui affiche la page du site sans
  /// quitter l'application, avec son état d'erreur et son bouton « ouvrir à
  /// l'extérieur ». Trois comportements coexistaient donc pour trois liens qui
  /// font la même chose.
  ///
  /// Sur le paywall, l'écart comptait le plus : envoyer quelqu'un dans Chrome
  /// au moment où il décide de payer, c'est le perdre. La webview satisfait la
  /// même exigence — des conditions publiques, vérifiables, citables — sans
  /// faire sortir de l'application.
  ///
  /// L'échec reste dit : la webview affiche son propre état d'erreur quand la
  /// page ne charge pas. Un lien légal qui ne fait rien quand on le touche est
  /// le défaut que ce projet a déjà corrigé deux fois.
  static void ouvrir(BuildContext context, String url, {String titre = ''}) {
    HapticFeedback.selectionClick();
    context.push('/navigateur', extra: {'url': url, 'title': titre});
  }

  /// Le titre de la barre, pour chaque page.
  static const String titreCgu = 'Conditions d\'utilisation';
  static const String titreConfidentialite = 'Politique de confidentialité';
}
