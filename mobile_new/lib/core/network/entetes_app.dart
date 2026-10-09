import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/distribution_channel.dart';

/// L'application se présente au serveur : version, build, plateforme, canal.
///
/// Le serveur ignorait quelle version chaque membre utilisait. Le panneau ne
/// pouvait donc pas dire combien restaient sur une version ancienne — ni
/// lesquels relancer avant de relever la version minimale, au risque de
/// bloquer d'un coup ceux qui n'avaient pas fait la mise à jour.
///
/// Ces en-têtes ne partent que vers l'API PronoWin (voir `DioClient`) : ils
/// ne disent rien du téléphone ni de la personne, seulement de l'application.
class EntetesApp {
  static Future<Map<String, String>>? _entetes;

  /// Lus une fois : la version installée ne change pas en cours d'exécution.
  static Future<Map<String, String>> lire(CanalDistribution? Function() canal) =>
      _entetes ??= _construire(canal);

  static Future<Map<String, String>> _construire(CanalDistribution? Function() canal) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.version.isEmpty) return const {};
      CanalDistribution? c;
      try { c = canal(); } catch (_) { c = null; }
      return {
        'X-App-Version':    pkg.version,
        if (pkg.buildNumber.isNotEmpty) 'X-App-Build': pkg.buildNumber,
        'X-App-Plateforme': plateforme(),
        if (c != null) 'X-App-Canal': c.name,
      };
    } catch (_) {
      // Sans information de version, l'application fonctionne comme avant :
      // rien ici ne doit pouvoir faire échouer une requête.
      return const {};
    }
  }

  @visibleForTesting
  static String plateforme() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'autre';
  }

  @visibleForTesting
  static void reinitialiser() => _entetes = null;
}
