import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La demande de note de la boutique.
///
/// Refus Apple du 2 novembre 2026 (règle 5.6.3) : la note était demandée au
/// lancement, dès la troisième ouverture — le relecteur l'a vue avant d'avoir
/// pu juger l'app. Elle ne part plus jamais au lancement : seulement pendant
/// la lecture d'une fiche de match, après une vraie utilisation (cinq
/// ouvertures sur sept jours au moins, trois fiches lues), puis pas avant
/// trente jours.
class ReviewService {
  static const _kOuvertures = 'review_session_count';
  static const _kConsultations = 'review_meaningful_engagement_count';
  static const _kPremiereOuverture = 'review_first_session_ms';
  static const _kDerniereDemande = 'review_last_asked_ms';

  static const _ouverturesMin = 5;
  static const _consultationsMin = 3;
  static const _joursDepuisPremiereOuverture = 7;
  static const _joursEntreDemandes = 30;

  /// À chaque lancement : compte l'ouverture, ne demande jamais rien.
  static Future<void> onSessionStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kPremiereOuverture)) {
        await prefs.setInt(_kPremiereOuverture, DateTime.now().millisecondsSinceEpoch);
      }
      await prefs.setInt(_kOuvertures, (prefs.getInt(_kOuvertures) ?? 0) + 1);
    } catch (_) {
      // Silencieux — ne doit jamais bloquer l'app
    }
  }

  /// Une fiche de match lue 30 secondes : la seule occasion de demander une
  /// note, si l'utilisation le justifie.
  static Future<void> consultationReelle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kConsultations, (prefs.getInt(_kConsultations) ?? 0) + 1);
      if (!_peutDemander(prefs)) return;
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await review.requestReview();
      await prefs.setInt(_kDerniereDemande, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_kConsultations, 0);
    } catch (_) {
      // Une demande de note reste facultative.
    }
  }

  static bool _peutDemander(SharedPreferences prefs) {
    final maintenant = DateTime.now();
    int joursDepuis(String cle) =>
        maintenant.difference(DateTime.fromMillisecondsSinceEpoch(prefs.getInt(cle)!)).inDays;
    if (prefs.containsKey(_kDerniereDemande) && joursDepuis(_kDerniereDemande) < _joursEntreDemandes) {
      return false;
    }
    return prefs.containsKey(_kPremiereOuverture)
        && joursDepuis(_kPremiereOuverture) >= _joursDepuisPremiereOuverture
        && (prefs.getInt(_kOuvertures) ?? 0) >= _ouverturesMin
        && (prefs.getInt(_kConsultations) ?? 0) >= _consultationsMin;
  }
}
