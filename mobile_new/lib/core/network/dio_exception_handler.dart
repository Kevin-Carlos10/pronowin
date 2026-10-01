import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'failures.dart';
import '../services/crashlytics_service.dart';

/// Convertit toute DioException en Failure lisible.
/// Tous les datasources doivent utiliser cette fonction — ne plus dupliquer _handle localement.
Failure handleDioException(DioException e, {String? context}) {
  final Failure failure;

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
      failure =  NetworkFailure("Connexion trop lente. Vérifie ton réseau.");
      break;
    case DioExceptionType.receiveTimeout:
      failure =  NetworkFailure("Le serveur met trop de temps à répondre.");
      break;
    case DioExceptionType.sendTimeout:
      failure =  NetworkFailure("Envoi de données trop lent. Vérifie ta connexion.");
      break;
    case DioExceptionType.connectionError:
      failure =  NetworkFailure("Impossible de joindre le serveur. Vérifie ton réseau.");
      break;
    case DioExceptionType.badResponse:
      final status  = e.response?.statusCode;
      final msg     = e.response?.data?['message'] as String?;
      if (status == 401) {
        failure = const UnauthorizedFailure();
      } else if (status == 403) {
        failure =  ServerFailure("Accès refusé.");
      } else if (status == 404) {
        failure =  ServerFailure("Ressource introuvable.");
      } else if (status == 429) {
        failure =  ServerFailure("Trop de requêtes. Réessaie dans quelques secondes.");
      } else if (status != null && status >= 500) {
        failure = ServerFailure("Erreur serveur ({arg0}). Réessaie plus tard.", [status]);
        CrashlyticsService.recordError(e, e.stackTrace,
            context: 'HTTP $status${context != null ? " · $context" : ""}');
      } else {
        failure = msg == null ? ServerFailure("Erreur inattendue ({arg0}).", [status]) : ServerFailure(msg);
      }
      break;
    case DioExceptionType.cancel:
      failure = const UnknownFailure();
      break;
    default:
      failure = const UnknownFailure();
      if (!kDebugMode) {
        CrashlyticsService.recordError(e, e.stackTrace,
            context: 'DioException(${e.type})${context != null ? " · $context" : ""}');
      }
  }

  return failure;
}
