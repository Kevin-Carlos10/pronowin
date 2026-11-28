import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Nom de la tâche périodique qu'enregistraient les versions précédentes.
const _kSyncTask     = 'pronowin.sync_matches';
const _kSyncTaskUniq = 'sync_matches_periodic';

/// Point d'entrée Dart pour les tâches WorkManager (top-level obligatoire).
///
/// Il reste déclaré pour une raison : une tâche enregistrée par une version
/// précédente peut se déclencher avant que [BackgroundSyncService.retirer]
/// ne l'ait annulée. Elle se termine alors sans rien faire.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async => true);
}

/// La synchronisation de fond, retirée.
///
/// Elle réveillait le téléphone toutes les 15 minutes, indéfiniment, même chez
/// qui n'ouvrait plus l'application (constat M4 de l'audit du 24 septembre
/// 2026) — pour écrire les matchs sous une clé que plus aucun écran ne lisait
/// (`cache_matches_all_week_all`, quand la liste lit
/// `matches_<sport>_<période>_…`). Et pour s'authentifier, elle recopiait le
/// jeton d'accès en clair dans les préférences, que la sauvegarde Android
/// emporte (constat M8) — un jeton de 15 minutes, périmé la plupart du temps
/// quand la tâche s'exécutait.
///
/// L'accueil se rafraîchit déjà à l'ouverture et quand il redevient visible :
/// cette tâche n'ajoutait que de la consommation. Elle est annulée sur les
/// téléphones qui l'avaient, et ses traces effacées.
class BackgroundSyncService {
  static Future<void> init() async {
    if (kIsWeb) return;
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  /// Annule la tâche des versions précédentes et efface ce qu'elle laissait.
  static Future<void> retirer() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(_kSyncTaskUniq);
    } catch (e) {
      debugPrint('[BgSync] annulation impossible : $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token_bg');
    await prefs.remove('cache_matches_all_week_all');
  }

  /// Nom conservé pour les tests qui vérifient qu'aucune tâche n'est plus
  /// enregistrée.
  static String get nomTacheRetiree => _kSyncTask;
}
