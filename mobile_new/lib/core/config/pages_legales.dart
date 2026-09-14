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
/// Regroupé ici pour la même raison que `BookmakerAffiliation.ouvrir` : quatre
/// écrans mènent à ces pages, et quatre copies d'un même `launchUrl`
/// divergeraient sur le mode d'ouverture ou sur ce qui se passe quand il
/// échoue.
class PagesLegales {
  /// Conditions générales d'utilisation, pour le canal donné.
  static String cgu({required bool estStore}) => estStore
      ? '${AppConstants.siteUrl}/cgu'
      : '${AppConstants.siteUrl}/cgu?canal=direct';

  /// Politique de confidentialité — l'URL déclarée à Google Play.
  static String get confidentialite => '${AppConstants.siteUrl}/confidentialite';

  /// Ouvre une page légale dans le navigateur du système.
  ///
  /// L'échec est dit, pas avalé. Un lien légal qui ne fait rien quand on le
  /// touche est le défaut que ce projet a déjà corrigé deux fois : d'abord
  /// trois mentions qui ressemblaient à des liens sans en être, puis un bouton
  /// « Confirmer » sans gestionnaire. Hors connexion, `launchUrl` échoue ou
  /// rend `false` — dans les deux cas l'utilisateur doit l'apprendre.
  static Future<void> ouvrir(BuildContext context, String url) async {
    HapticFeedback.selectionClick();
    try {
      final ouverte = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (ouverte) return;
      throw StateError('launchUrl a refusé $url');
    } catch (e) {
      debugPrint('[PagesLegales] Ouverture impossible : $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible de joindre le site. Vérifiez votre connexion.'),
      ));
    }
  }
}
