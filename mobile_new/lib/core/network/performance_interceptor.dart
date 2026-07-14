import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Mesure chaque requête Dio avec Firebase Performance HTTP Metrics.
/// Désactivé en debug (pas de données dans la console Firebase pour dev).
class PerformanceInterceptor extends Interceptor {
  final _perf = FirebasePerformance.instance;

  // On stocke la métrique en cours dans les extra de la requête
  // pour la récupérer dans onResponse / onError.
  static const _kMetric = '_perf_metric';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!kDebugMode) {
      try {
        final url      = '${options.baseUrl}${options.path}';
        final httpMethod = HttpMethod.values.firstWhere(
          (m) => m.name == options.method.toUpperCase(),
          orElse: () => HttpMethod.Get,
        );
        final metric = _perf.newHttpMetric(url, httpMethod);
        await metric.start();
        options.extra[_kMetric] = metric;
      } catch (_) {}
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    await _stop(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    await _stop(err.requestOptions, err.response?.statusCode ?? 0);
    handler.next(err);
  }

  Future<void> _stop(RequestOptions options, int? statusCode) async {
    try {
      final metric = options.extra[_kMetric] as HttpMetric?;
      if (metric == null) return;
      metric.httpResponseCode = statusCode;
      await metric.stop();
    } catch (_) {}
  }
}
