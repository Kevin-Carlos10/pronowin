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

  /// Nom affiché du partenaire.
  static const String nom = '1xBet';

  /// Lien d'affiliation 1xPartners.
  static const String lien =
      'https://reffpa.com/L?tag=d_1793663m_97c_&site=1793663&ad=97';

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
    try {
      await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Affiliation] Ouverture impossible : $e');
    }
  }
}
