import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Remote Config.
///
/// Valeurs par défaut identiques aux variables d'env backend.
/// Pour changer le comportement de l'app sans déploiement :
///   1. Firebase Console → Remote Config
///   2. Modifier la clé souhaitée
///   3. Publier — l'app récupère les nouvelles valeurs au prochain démarrage
class RemoteConfigService {
  static final _rc = FirebaseRemoteConfig.instance;

  static const _defaults = <String, dynamic>{
    'min_version':      '1.0.0',
    'latest_version':   '1.0.0',
    'force_update':     false,
    'update_message':   'Une nouvelle version de PronoWin est disponible avec des améliorations importantes.',
    'maintenance_mode': false,
    'maintenance_msg':  'PronoWin est en maintenance. Revenez dans quelques minutes.',
  };

  static Future<void> init() async {
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        // En debug : fetch immédiat (pas de cache) pour faciliter les tests
        fetchTimeout:        const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ));
      await _rc.setDefaults(_defaults);
      await _rc.fetchAndActivate();
    } catch (e) {
      debugPrint('[RemoteConfig] Init error: $e — defaults will be used');
    }
  }

  static String  get minVersion     => _rc.getString('min_version');
  static String  get latestVersion  => _rc.getString('latest_version');
  static bool    get forceUpdate    => _rc.getBool('force_update');
  static String  get updateMessage  => _rc.getString('update_message');
  static bool    get maintenanceMode => _rc.getBool('maintenance_mode');
  static String  get maintenanceMsg  => _rc.getString('maintenance_msg');
}
