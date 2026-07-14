import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheEntry<T> {
  final T data;
  final DateTime cachedAt;
  final bool isExpired;

  const CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.isExpired,
  });
}

class CacheService {
  // TTL adaptatif selon l'endpoint
  static Duration ttlFor(String key) {
    if (key.contains('actualites'))       return const Duration(hours: 1);
    if (key.contains('stats'))            return const Duration(minutes: 10);
    if (key.contains('pronostics'))       return const Duration(minutes: 5);
    if (key.contains('favorites'))        return const Duration(minutes: 5);
    if (key.contains('notifications'))    return const Duration(minutes: 2);
    return const Duration(hours: 1);
  }

  static Future<void> save(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'ts':   DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
    await prefs.setString('cache_$key', payload);
  }

  /// Charge les données si le TTL n'est pas expiré.
  static Future<T?> load<T>(String key, T Function(dynamic) fromJson) async {
    final entry = await loadWithMeta(key, fromJson);
    if (entry == null || entry.isExpired) return null;
    return entry.data;
  }

  /// Charge les données avec métadonnées (même si expirées).
  static Future<CacheEntry<T>?> loadWithMeta<T>(
    String key,
    T Function(dynamic) fromJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('cache_$key');
      if (raw == null) return null;

      final payload   = jsonDecode(raw) as Map<String, dynamic>;
      final ts        = payload['ts'] as int;
      final cachedAt  = DateTime.fromMillisecondsSinceEpoch(ts);
      final ttl       = ttlFor(key);
      final isExpired = DateTime.now().difference(cachedAt) > ttl;

      return CacheEntry(
        data:      fromJson(payload['data']),
        cachedAt:  cachedAt,
        isExpired: isExpired,
      );
    } catch (_) {
      return null;
    }
  }

  /// Charge sans tenir compte du TTL — retourne directement la donnée (dernier recours hors ligne).
  static Future<T?> loadStale<T>(String key, T Function(dynamic) fromJson) async {
    final entry = await loadStaleEntry(key, fromJson);
    return entry?.data;
  }

  /// Charge sans tenir compte du TTL — retourne un [CacheEntry] avec métadonnées.
  static Future<CacheEntry<T>?> loadStaleEntry<T>(
    String key,
    T Function(dynamic) fromJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('cache_$key');
      if (raw == null) return null;
      final payload  = jsonDecode(raw) as Map<String, dynamic>;
      final ts       = payload['ts'] as int;
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(ts);
      return CacheEntry(
        data:      fromJson(payload['data']),
        cachedAt:  cachedAt,
        isExpired: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cache_$key');
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
