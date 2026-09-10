import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../constants/app_constants.dart';
import '../services/crashlytics_service.dart';
import '../storage/secure_storage.dart';
import 'cache_interceptor.dart';
import 'performance_interceptor.dart';

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(secureStorageProvider);
  return DioClient(storage, ref).dio;
});

class DioClient {
  late final Dio dio;
  final SecureStorageService _storage;
  final Ref _ref;

  // ── Protection contre les refreshs concurrents ───────────────────────────
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  /// Fabrique de l'instance Dio dédiée au rafraîchissement.
  ///
  /// Le rafraîchissement passe volontairement par un Dio vierge, pour ne pas
  /// retraverser l'intercepteur qui l'a déclenché — sans quoi un 401 sur le
  /// rafraîchissement lui-même relancerait un rafraîchissement, en boucle.
  ///
  /// Conséquence : cette instance échappe à tout adaptateur posé sur `dio`,
  /// et le chemin « 401 → rafraîchissement → rejeu » n'était donc pas
  /// testable de bout en bout. C'est précisément le chemin sur lequel un
  /// défaut est passé inaperçu six semaines. Cette couture existe pour qu'il
  /// soit observable ; elle n'est pas utilisée en production.
  @visibleForTesting
  static Dio Function()? fabriqueDioRafraichissement;

  // Endpoints publics, appelés sans session existante — un 401 dessus est
  // toujours une erreur métier (code invalide ou expiré), jamais un jeton
  // périmé. Ne doit jamais déclencher _doRefresh().
  /// Marque posée sur une requête déjà rejouée après rafraîchissement.
  ///
  /// `dio.fetch` retraverse toute la chaîne d'intercepteurs, y compris celui-ci.
  /// Sans marque, un rejeu qui reçoit lui aussi un 401 relance un
  /// rafraîchissement, qui rejoue, qui reçoit un 401 — indéfiniment, en
  /// martelant le serveur. Le rafraîchissement réussit à chaque tour (le jeton
  /// de session, lui, est valide), donc rien n'arrête la boucle.
  ///
  /// Un rejeu et un seul : si le jeton neuf est refusé, la réponse est
  /// définitive et doit remonter à l'appelant.
  static const _dejaRejoue = '_auth_deja_rejoue';

  static const _publicAuthEndpoints = <String>{
    ApiEndpoints.sendOtp,
    ApiEndpoints.verifyOtp,
    ApiEndpoints.sendEmailOtp,
    ApiEndpoints.verifyEmailOtp,
    ApiEndpoints.refreshToken,
  };

  /// [telemetrie] : installe l'intercepteur Firebase Performance.
  ///
  /// Faux uniquement en test. Cet intercepteur résout
  /// `FirebasePerformance.instance` dès sa construction et lève donc si
  /// Firebase n'a pas démarré — ce qui rend le client HTTP inconstructible
  /// hors application, et avec lui tout le chemin « 401 →
  /// rafraîchissement → rejeu ». C'est ce chemin qui a laissé passer, six
  /// semaines durant, un écran proposant de créer un compte à des
  /// utilisateurs connectés.
  ///
  /// Rendre le champ paresseux réglait cela d'un mot, mais seize tests de
  /// mise en page passaient *parce que* cette construction échouait : leurs
  /// widgets n'émettaient aucune requête. Les débloquer les faisait échouer
  /// sur des minuteurs en attente. Le défaut de production reste donc
  /// inchangé, et seul le test s'en écarte — explicitement.
  DioClient(this._storage, this._ref, {bool telemetrie = true}) {
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
    if (telemetrie) dio.interceptors.add(PerformanceInterceptor());
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
          // Un 401 sur ces endpoints publics (pas encore de session) est une
          // erreur métier normale (mauvais code/identifiants) — pas un signe
          // que le token d'accès a été rejeté. Tenter un refresh dessus n'a
          // aucun sens (pas de refresh token) et déclenchait une réinitialisation
          // globale de authProvider en pleine course avec le catch de l'appelant
          // (ex: "Code OTP invalide" pendant la vérification email → crash).
          final isPublicAuthEndpoint = _publicAuthEndpoints
              .any((p) => error.requestOptions.path.contains(p));

          final dejaRejoue = error.requestOptions.extra[_dejaRejoue] == true;

          if (error.response?.statusCode == 401 &&
              !isPublicAuthEndpoint &&
              !dejaRejoue) {
            final refreshed = await _doRefresh();
            if (refreshed) {
              // Rejouer la requête originale avec le nouveau token
              final token = await _storage.read(AppConstants.accessTokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              error.requestOptions.extra[_dejaRejoue] = true;
              try {
                final retryResp = await dio.fetch(error.requestOptions);
                return handler.resolve(retryResp);
              } catch (retryErr) {
                // Le rejeu a échoué — mais pas forcément pour la même raison.
                //
                // Cette ligne renvoyait le 401 d'origine quoi qu'il arrive. Or
                // le rejeu part juste après un rafraîchissement, souvent au
                // milieu d'une rafale de requêtes : un délai dépassé ou une
                // coupure y est banal. Le signaler comme un 401 est un
                // contresens, parce que 401 ne veut pas dire « ça a raté » —
                // dans cette application, il veut dire « pas de compte ».
                //
                // Observé sur l'émulateur : session parfaitement valide,
                // `/auth/profile` répondant, et la fiche de match proposant
                // « Crée ton compte pour voir l'analyse ». L'écran ne plante
                // pas, ne signale rien, et affirme le faux — au seul endroit
                // où l'utilisateur cherche à comprendre le pronostic.
                //
                // Un vrai 401 au rejeu reste un 401 : le jeton neuf a été
                // refusé, la conclusion est juste. C'est le reste qui ne doit
                // plus emprunter son code.
                return handler.next(
                  retryErr is DioException ? retryErr : error);
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
      final freshDio = fabriqueDioRafraichissement?.call() ?? Dio(BaseOptions(
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
      // ── Un échec réseau n'est pas un refus ────────────────────────────────
      //
      // Cette branche appelait `deleteAll()` sur **n'importe quelle** exception.
      // Une coupure réseau détruisait donc la session, définitivement : les
      // jetons effacés, plus rien à restaurer au retour de la connexion.
      //
      // Le symptôme rapporté était « je redémarre le téléphone et je suis
      // déconnecté ». C'en est la conséquence directe : le jeton d'accès vit
      // quinze minutes, il est donc toujours expiré après un redémarrage, et le
      // rafraîchissement part au moment précis où Android n'a pas fini de
      // rétablir le réseau. La requête échoue, et la session part avec elle.
      //
      // On n'efface plus que sur un refus **explicite** du serveur. Tout le
      // reste — pas de réponse, délai dépassé, réponse illisible — laisse les
      // jetons en place : la requête suivante réessaiera.
      final refuse = e is DioException &&
          e.response != null &&
          (e.response!.statusCode == 401 || e.response!.statusCode == 403);

      if (refuse) {
        debugPrint('[DioClient] ❌ Refresh refusé par le serveur → déconnexion');
        await _storage.deleteAll();
        _onRefreshFailed();
      } else {
        debugPrint('[DioClient] ⚠️ Refresh injoignable ($e) — jetons conservés');
      }

      _refreshCompleter!.complete(false);
      return false;

    } finally {
      _isRefreshing     = false;
      _refreshCompleter = null;
    }
  }

  /// Rétrograde silencieusement en mode invité quand le refresh échoue —
  /// ne force plus la navigation vers l'écran de connexion. Le router
  /// (qui écoute authProvider/isLoggedInProvider) redirigera de lui-même
  /// vers /auth/email UNIQUEMENT si l'écran courant l'exige ; sinon
  /// l'utilisateur continue de naviguer normalement en invité.
  void _onRefreshFailed() {
    // Différé pour éviter de modifier le provider tree pendant un build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Déjà invité (AuthInitial) — ne rien faire. Éviter de notifier pour
      // rien évite une cascade de rebuild/redirection au démarrage, quand
      // un simple appel anonyme (ex. FCM) échoue en 401 alors qu'aucune
      // session n'a jamais existé.
      if (_ref.read(authProvider) is AuthInitial) return;
      debugPrint('[DioClient] Session expirée → retour en mode invité');
      _ref.read(authProvider.notifier).reset();
      _ref.invalidate(isLoggedInProvider);
    });
  }
}

/// Décalage UTC de l'appareil, en minutes (60 pour UTC+1).
///
/// Transmis au serveur sur les requêtes filtrées par jour : sans lui, le
/// backend découpe les journées dans *son* fuseau et le mobile dans celui de
/// l'utilisateur. Un match de fin de soirée tombait alors du mauvais côté de
/// minuit pour l'un des deux, et le compteur du bandeau ne correspondait plus
/// aux cartes affichées en dessous.
int decalageUtcMinutes() => DateTime.now().timeZoneOffset.inMinutes;
