import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  static final _c = FirebaseCrashlytics.instance;

  static Future<void> init() async {
    await _c.setCrashlyticsCollectionEnabled(!kDebugMode);
  }

  /// Enregistre une erreur non fatale avec contexte.
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    if (kDebugMode) {
      debugPrint('[Crashlytics${fatal ? " FATAL" : ""}] $context: $error');
      return;
    }
    _c.recordError(error, stack,
        reason: context, fatal: fatal, printDetails: false);
  }

  /// Définit l'ID utilisateur pour regrouper les sessions Crashlytics.
  static Future<void> setUser(String userId) =>
      _c.setUserIdentifier(userId);

  static Future<void> clearUser() => _c.setUserIdentifier('');

  /// Clé/valeur arbitraire attachée aux rapports.
  static Future<void> setKey(String key, String value) =>
      _c.setCustomKey(key, value);

  /// Log texte visible dans le rapport Crashlytics (breadcrumb).
  static void log(String msg) {
    if (!kDebugMode) _c.log(msg);
  }
}
