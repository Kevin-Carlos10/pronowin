import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../router/navigation_keys.dart';
import '../services/crashlytics_service.dart';
import '../storage/secure_storage.dart';
import 'cache_interceptor.dart';
import 'performance_interceptor.dart';

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(secureStorageProvider);
  return DioClient(storage).dio;
});

class DioClient {
  late final Dio dio;
  final SecureStorageService _storage;

  // ── Protection contre les refreshs concurrents ───────────────────────────
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  DioClient(this._storage) {
    dio = Dio(
      BaseOptions(
        baseUrl:        AppConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
      ),
    );
    _setupCertificatePinning();
    _addInterceptors();
    dio.interceptors.add(CacheInterceptor());
    dio.interceptors.add(PerformanceInterceptor());
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CERTIFICATE PINNING
  // ════════════════════════════════════════════════════════════════════════════
  //
  // Stratégie : on pine les empreintes SHA-256 du certificat DER (leaf pinning).
  // Pour obtenir l'empreinte du certificat de production :
  //
  //   openssl s_client -connect api.pronowin.com:443 -servername api.pronowin.com \
  //     </dev/null 2>/dev/null \
  //     | openssl x509 -outform DER \
  //     | openssl dgst -sha256
  //
  // Exemple de sortie : SHA2-256(stdin)= a1b2c3d4e5f6...
  // Copier la valeur hex (sans espaces) dans _pinnedSha256.
  //
  // ⚠️  Règles importantes :
  //   • Toujours mettre AU MOINS 2 empreintes (cert actuel + cert de rotation)
  //     avant de déployer pour éviter de bloquer tous les utilisateurs lors
  //     d'un renouvellement de certificat.
  //   • Le pinning ne s'applique QU'au host de production (_productionHost).
  //     Les envs de dev/staging ne sont pas concernés.
  //   • En cas de compromission, changer l'empreinte + forcer une mise à jour
  //     via APP_FORCE_UPDATE=true dans le backend.

  static const _productionHost = 'api.pronowin.com';

  // Empreintes SHA-256 (hex lowercase, sans séparateurs) des certificats autorisés.
  // Laisser vide = pinning désactivé (ne bloquer aucun utilisateur avant d'avoir
  // les vraies empreintes).
  static const _pinnedSha256 = <String>{
    // Certificat actuel — à remplir avant le déploiement HTTPS
    // 'a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890ab',
    // Certificat de rotation (backup) — à préparer AVANT le renouvellement
    // 'b2c3d4e5f6789012345678901234567890123456789012345678901234567890abcd',
  };

  void _setupCertificatePinning() {
    // Pas de pinning en debug (permet de travailler avec un serveur local HTTP)
    if (kDebugMode) return;

    // Pas de pinning si aucune empreinte n'est configurée
    if (_pinnedSha256.isEmpty) {
      // Avertissement visible dans les logs release si on oublie de configurer
      debugPrint('[CertPin] ⚠️  Aucune empreinte configurée — pinning désactivé');
      return;
    }

    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          // N'appliquer le pinning que sur le host de production
          if (host != _productionHost) return false;

          final fingerprint = sha256.convert(cert.der).toString();
          final allowed     = _pinnedSha256.contains(fingerprint);

          if (!allowed) {
            debugPrint(
              '[CertPin] ❌ Certificat NON autorisé pour $host\n'
              '  Empreinte reçue : $fingerprint\n'
              '  Empreintes attendues : $_pinnedSha256',
            );
            // Logguer en Crashlytics pour détecter une attaque MITM en prod
            CrashlyticsService.recordError(
              Exception('CertPin: certificat non autorisé pour $host ($fingerprint)'),
              null,
              context: 'certificate_pinning',
            );
          }
          return allowed;
        };
      return client;
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  // INTERCEPTEURS
  // ════════════════════════════════════════════════════════════════════════════

  void _addInterceptors() {
    // Logging (dev uniquement)
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody:  true,
        responseBody: true,
        logPrint:     (o) => debugPrint('[DIO] $o'),
      ));
    }

    // Auth token + auto-refresh
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(AppConstants.accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          // Ne pas tenter de refresh sur l'endpoint de refresh lui-même
          final isRefreshEndpoint =
              error.requestOptions.path.contains(ApiEndpoints.refreshToken);

          if (error.response?.statusCode == 401 && !isRefreshEndpoint) {
            final refreshed = await _doRefresh();
            if (refreshed) {
              // Rejouer la requête originale avec le nouveau token
              final token = await _storage.read(AppConstants.accessTokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              try {
                final retryResp = await dio.fetch(error.requestOptions);
                return handler.resolve(retryResp);
              } catch (retryErr) {
                return handler.next(error);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // REFRESH TOKEN AVEC ROTATION + PROTECTION CONCURRENCE
  // ════════════════════════════════════════════════════════════════════════════

  /// Effectue le refresh token de manière thread-safe.
  ///
  /// Si un refresh est déjà en cours, les appelants concurrents attendent
  /// la même réponse plutôt que de lancer plusieurs requêtes en parallèle.
  Future<bool> _doRefresh() async {
    // ── Déjà en cours → attendre le résultat ─────────────────────────────────
    if (_isRefreshing) {
      debugPrint('[DioClient] Refresh déjà en cours — attente...');
      return _refreshCompleter!.future;
    }

    _isRefreshing     = true;
    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _storage.read(AppConstants.refreshTokenKey);
      if (refreshToken == null) {
        debugPrint('[DioClient] Pas de refresh token → déconnexion');
        _onRefreshFailed();
        _refreshCompleter!.complete(false);
        return false;
      }

      // Utiliser une instance Dio vierge pour éviter les boucles d'intercepteurs
      final freshDio = Dio(BaseOptions(
        baseUrl:        AppConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
      ));

      final response = await freshDio.post(
        ApiEndpoints.refreshToken,
        data: {'refresh_token': refreshToken},
      );

      final newAccessToken  = response.data['access_token']  as String?;
      final newRefreshToken = response.data['refresh_token'] as String?;

      if (newAccessToken == null || newRefreshToken == null) {
        throw Exception('Réponse refresh invalide');
      }

      // ── Sauvegarder la paire rotée ──────────────────────────────────────────
      await _storage.write(AppConstants.accessTokenKey,  newAccessToken);
      await _storage.write(AppConstants.refreshTokenKey, newRefreshToken);

      debugPrint('[DioClient] ✅ Tokens rotés avec succès');
      _refreshCompleter!.complete(true);
      return true;

    } catch (e) {
      debugPrint('[DioClient] ❌ Refresh échoué : $e');
      await _storage.deleteAll();
      _onRefreshFailed();
      _refreshCompleter!.complete(false);
      return false;

    } finally {
      _isRefreshing     = false;
      _refreshCompleter = null;
    }
  }

  /// Redirige vers la page de connexion quand le refresh échoue.
  void _onRefreshFailed() {
    // Ajouter au prochain frame pour éviter les navigations pendant un build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        debugPrint('[DioClient] Session expirée → redirection /auth/phone');
        ctx.go('/auth/phone');
      }
    });
  }
}
