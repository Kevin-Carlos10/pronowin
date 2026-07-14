import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../cache/cache_service.dart';

/// Intercepteur Dio avec stratégie stale-while-revalidate :
/// - En ligne  : laisse passer la requête, sauvegarde la réponse en cache.
/// - Hors ligne : sert immédiatement le cache (même expiré) avec header x-from-cache.
/// - Erreur réseau : idem fallback cache.
class CacheInterceptor extends Interceptor {
  // Seules les requêtes GET sont mises en cache
  static bool _isCacheable(RequestOptions options) =>
      options.method.toUpperCase() == 'GET';

  static String _cacheKey(RequestOptions options) {
    final q = options.queryParameters.isNotEmpty
        ? '_${options.queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    return '${options.path}$q';
  }

  // ── Requête sortante ──────────────────────────────────────────────────────────
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isCacheable(options)) return handler.next(options);

    // Si l'appelant a mis extra['forceRefresh'] = true, bypass le cache
    final forceRefresh = options.extra['forceRefresh'] == true;
    if (forceRefresh) return handler.next(options);

    // Vérifier la connectivité via le flag passé en extra (set par les providers)
    final isOffline = options.extra['offline'] == true;

    if (isOffline) {
      final key   = _cacheKey(options);
      final entry = await CacheService.loadStaleEntry<dynamic>(key, (d) => d);
      if (entry != null) {
        debugPrint('[Cache] STALE served (offline): $key');
        return handler.resolve(_buildCachedResponse(options, entry.data, stale: true));
      }
      // Pas de cache disponible — laisser Dio échouer normalement
      return handler.next(options);
    }

    return handler.next(options);
  }

  // ── Réponse reçue ─────────────────────────────────────────────────────────────
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (_isCacheable(response.requestOptions) && response.statusCode == 200) {
      final key = _cacheKey(response.requestOptions);
      try {
        await CacheService.save(key, response.data);
        debugPrint('[Cache] SAVED: $key');
      } catch (e) {
        debugPrint('[Cache] Save error: $e');
      }
    }
    handler.next(response);
  }

  // ── Erreur réseau → fallback cache ────────────────────────────────────────────
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (!_isCacheable(options)) return handler.next(err);

    // Tentative de fallback uniquement sur erreurs réseau (pas 4xx / 5xx serveur)
    final isNetworkError = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.unknown;

    if (!isNetworkError) return handler.next(err);

    final key   = _cacheKey(options);
    final entry = await CacheService.loadStaleEntry<dynamic>(key, (d) => d);

    if (entry != null) {
      debugPrint('[Cache] FALLBACK (network error): $key — age: ${DateTime.now().difference(entry.cachedAt).inMinutes} min');
      return handler.resolve(_buildCachedResponse(options, entry.data, stale: true));
    }

    handler.next(err);
  }

  // ── Fabrique une Response Dio à partir du cache ───────────────────────────────
  static Response _buildCachedResponse(
    RequestOptions options,
    dynamic data, {
    bool stale = false,
  }) {
    return Response(
      requestOptions: options,
      data:           data,
      statusCode:     200,
      headers:        Headers.fromMap({
        'x-from-cache': [stale ? 'stale' : 'fresh'],
        'content-type': ['application/json'],
      }),
    );
  }
}
