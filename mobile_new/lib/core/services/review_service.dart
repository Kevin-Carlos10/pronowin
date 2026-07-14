import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static const _kCount    = 'review_session_count';
  static const _kLastDate = 'review_last_asked_ms';

  // Demander après 3 sessions, puis pas avant 30 jours
  static const _threshold   = 3;
  static const _cooldownDays = 30;

  /// À appeler une fois au démarrage de l'app (après l'init Firebase).
  static Future<void> onSessionStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Vérifier le cooldown
      final lastMs = prefs.getInt(_kLastDate) ?? 0;
      if (lastMs > 0) {
        final daysSince =
            DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastMs)).inDays;
        if (daysSince < _cooldownDays) return;
      }

      final count = (prefs.getInt(_kCount) ?? 0) + 1;
      await prefs.setInt(_kCount, count);

      if (count >= _threshold) {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
          // Réinitialiser le compteur + enregistrer la date
          await prefs.setInt(_kCount, 0);
          await prefs.setInt(
              _kLastDate, DateTime.now().millisecondsSinceEpoch);
        }
      }
    } catch (_) {
      // Silencieux — ne doit jamais bloquer l'app
    }
  }
}
