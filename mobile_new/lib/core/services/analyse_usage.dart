import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Le plan d'analyse d'usage de PronoWin (constat M2 de l'audit du
/// 24 septembre 2026).
///
/// Aucune mesure n'existait : impossible de savoir où l'on perd les gens
/// entre l'installation, l'inscription, le paywall, le paiement et
/// l'activation. Ce fichier est le plan complet — une dizaine d'événements,
/// chacun à un seul endroit du code, et rien d'autre ne part vers Firebase.
///
/// Aucune donnée personnelle : ni identifiant de compte, ni pseudo, ni
/// téléphone, ni montant. Des méthodes, des sources, des notes de confiance,
/// des booléens.
///
/// Entonnoir : `login` / `inscription` → `paywall_vu` → `methode_choisie` →
/// `preuve_envoyee` ou `achat_store_lance` → `premium_active`.
/// Usage : `pronostic_ouvert`, `pari_enregistre`, `mise_confirmee`,
/// `notification_ouverte`.
class AnalyseUsage {
  AnalyseUsage._();

  /// Pour les bancs : reçoit chaque événement au lieu de Firebase.
  @visibleForTesting
  static void Function(String nom, Map<String, Object> parametres)? espion;

  static Future<void> _envoyer(String nom, [Map<String, Object> parametres = const {}]) async {
    final e = espion;
    if (e != null) {
      e(nom, parametres);
      return;
    }
    try {
      await FirebaseAnalytics.instance.logEvent(name: nom, parameters: parametres);
    } catch (_) {
      // Firebase absent ou non initialisé : une mesure perdue ne doit jamais
      // interrompre ce que l'utilisateur est en train de faire.
    }
  }

  /// Session ouverte. [methode] : `email` ou `google`.
  static Future<void> connexion({required String methode, required bool nouveauCompte}) =>
      _envoyer(nouveauCompte ? 'inscription' : 'login', {'methode': methode});

  /// L'écran d'abonnement s'affiche.
  static Future<void> paywallVu() => _envoyer('paywall_vu');

  /// Moyen de paiement retenu : `direct` (Mobile Money), `code`, `store`.
  static Future<void> methodeChoisie(String methode) =>
      _envoyer('methode_choisie', {'methode': methode});

  /// Preuve de paiement Mobile Money, ou code promo, envoyée.
  static Future<void> preuveEnvoyee({required String methode, required String duree}) =>
      _envoyer('preuve_envoyee', {'methode': methode, 'duree': duree});

  /// Achat intégré lancé depuis le store.
  static Future<void> achatStoreLance(String duree) =>
      _envoyer('achat_store_lance', {'duree': duree});

  /// Premium actif, constaté par l'application sur le profil — une fois par
  /// échéance d'abonnement, quel que soit le canal. Le Mobile Money est
  /// activé par l'équipe, hors de l'application : c'est ici qu'on le voit.
  ///
  /// [dejaVu] / [marquer] : la mémoire de ce qui a été signalé (préférences
  /// locales en service, un ensemble en test).
  static Future<void> premiumConstate({
    required String? echeance,
    required Future<bool> Function(String cle) dejaVu,
    required Future<void> Function(String cle) marquer,
  }) async {
    if (echeance == null || echeance.isEmpty) return;
    final cle = 'analyse_premium_$echeance';
    if (await dejaVu(cle)) return;
    await marquer(cle);
    await _envoyer('premium_active');
  }

  /// Détail d'un pronostic ouvert.
  static Future<void> pronosticOuvert({required bool premium}) =>
      _envoyer('pronostic_ouvert', {'premium': premium ? 1 : 0});

  /// Mise enregistrée dans la bankroll, à la note de confiance donnée.
  static Future<void> pariEnregistre(int confiance) =>
      _envoyer('pari_enregistre', {'confiance': confiance});

  /// Mise réelle confirmée au résultat (M1) — corrigée ou non.
  static Future<void> miseConfirmee({required bool corrigee}) =>
      _envoyer('mise_confirmee', {'corrigee': corrigee ? 1 : 0});

  /// Notification ouverte, par type (`match`, `payment`, `promo`…).
  static Future<void> notificationOuverte(String type) =>
      _envoyer('notification_ouverte', {'type': type.isEmpty ? 'inconnu' : type});
}
