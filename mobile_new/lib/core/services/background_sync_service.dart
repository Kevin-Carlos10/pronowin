import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../constants/app_constants.dart';

const _kSyncTask      = 'pronowin.sync_matches';
const _kSyncTaskUniq  = 'sync_matches_periodic';

/// Point d'entrée Dart pour les tâches WorkManager (top-level obligatoire).
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName == _kSyncTask) {
      await _syncMatches();
    }
    return Future.value(true);
  });
}

/// Rafraîchit silencieusement le cache des matchs de la semaine.
Future<void> _syncMatches() async {
  try {
    final dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));

    // Lire le token d'accès depuis shared_preferences
    // (flutter_secure_storage n'est pas accessible en background sur Android)
    final prefs     = await SharedPreferences.getInstance();
    final token     = prefs.getString('access_token_bg');
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    final resp = await dio.get(
      ApiEndpoints.pronostics,
      queryParameters: {'date_filter': 'week', 'include_all': 'true', 'per_page': 100},
    );

    final list = resp.data['data'] as List<dynamic>?;
    if (list == null) return;

    // Écrire dans le cache partagé (même format que CacheService)
    final payload = jsonEncode({
      'ts':   DateTime.now().millisecondsSinceEpoch,
      'data': list,
    });
    await prefs.setString('cache_matches_all_week_all', payload);
    debugPrint('[BgSync] ✅ ${list.length} matchs mis en cache');
  } catch (e) {
    debugPrint('[BgSync] ❌ $e');
  }
}

class BackgroundSyncService {
  static Future<void> init() async {
    if (kIsWeb) return;
    await Workmanager().initialize(
      backgroundCallbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  static Future<void> registerPeriodicSync() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      _kSyncTaskUniq,
      _kSyncTask,
      // Minimum possible : 15 min sur Android (contrainte OS)
      frequency:        const Duration(minutes: 15),
      initialDelay:     const Duration(minutes: 5),
      constraints: Constraints(
        networkType:       NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    debugPrint('[BgSync] Tâche périodique enregistrée');
  }

  /// Enregistre le token dans SharedPreferences pour que la tâche background
  /// puisse l'utiliser (flutter_secure_storage non disponible en isolate).
  static Future<void> saveTokenForBackground(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token_bg', accessToken);
  }

  static Future<void> clearTokenForBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token_bg');
  }
}
