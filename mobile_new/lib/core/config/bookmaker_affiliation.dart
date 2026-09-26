import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Partenariat bookmaker — un seul endroit pour le lien d'affiliation.
///
/// Le lien porte l'identifiant de compte (`site`), l'étiquette de campagne
/// (`tag`) et le créatif (`ad`). Recopié à plusieurs endroits, il finirait par
/// diverger — et une divergence ici ne casse rien de visible : les clics
/// partent simplement sur un tag qui ne rapporte plus rien. C'est exactement le
/// genre de panne silencieuse qu'on ne découvre qu'au relevé mensuel.
class BookmakerAffiliation {
  const BookmakerAffiliation._();

  /// Nom et lien du partenaire — **servis par le serveur**.
  ///
  /// Ils etaient compiles dans le binaire. Le commentaire ci-dessus decrivait
  /// deja le risque — « une divergence ici ne casse rien de visible : les
  /// clics partent simplement sur un tag qui ne rapporte plus rien » — sans
  /// s'en proteger : changer le lien exigeait de republier l'application, puis
  /// d'attendre que chacun la mette a jour.
  ///
  /// Ces deux champs sont renseignes au demarrage depuis `/config`. Tant que
  /// rien n'est configure, ils restent vides et [disponible] vaut faux :
  /// l'application n'affiche alors **aucune** invitation a parier. Un lien
  /// mort vaut moins que pas de lien — il fait cliquer sans rien rapporter, et
  /// il use la confiance au passage.
  static String nom  = '';
  static String lien = '';

  /// Y a-t-il un partenariat a proposer ?
  static bool get disponible => lien.trim().isNotEmpty;

  /// Renseigne le partenariat depuis la reponse de `/config`.
  ///
  /// Silencieux et idempotent : appele au demarrage, il ne doit jamais
  /// empecher l'application de se lancer parce qu'un champ manque.
  static void configurer(Map<String, dynamic>? config) {
    final url = (config?['affiliateUrl'] as String?)?.trim() ?? '';
    if (!url.startsWith('http')) { lien = ''; nom = ''; return; }
    lien = url;
    nom  = (config?['affiliateName'] as String?)?.trim() ?? '';
  }

  /// Logo officiel du partenaire, fourni par le programme d'affiliation.
  ///
  /// Tant que le fichier n'est pas déposé, la tuile se replie sur un libellé
  /// texte : mieux vaut un mot lisible qu'une icône cassée, et surtout on
  /// n'invente pas une marque de mémoire — le créatif officiel se télécharge
  /// depuis l'espace partenaire.
  static const String logo = 'assets/images/bookmakers/1xbet-logo.png';

  /// Mention légale obligatoire sous une promotion de paris.
  static const String mention = 'Publicité · 18+ · Jouez responsable';

  /// Ouvre le lien partenaire dans le navigateur du système.
  ///
  /// Regroupé ici parce que plusieurs écrans y mènent désormais : le bandeau de
  /// cotes, la cote du pronostic, et la boîte de mise. Trois copies d'un même
  /// `launchUrl` finiraient par diverger sur le mode d'ouverture ou la gestion
  /// d'erreur.
  static Future<void> ouvrir() async {
    HapticFeedback.selectionClick();
    // `canLaunchUrl` répond faux sur Android quand aucune requête de visibilité
    // de paquet ne couvre le schéma : on tente l'ouverture, et on ne retient
    // l'échec que s'il se produit réellement.
    if (!disponible) return;
    try {
      await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Affiliation] Ouverture impossible : $e');
    }
  }
}
