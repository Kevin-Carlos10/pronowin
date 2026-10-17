import 'package:pronowin/l10n/app_strings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/navigation_keys.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'notification_service.dart';
import '../../../../core/services/analyse_usage.dart';

// ─── Handler background (top-level obligatoire) ───────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] ${message.notification?.title}');
}

class FCMService {

  static final _fcm   = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  /// Deep link en attente (app était tuée → on navigue après init du router)
  static String? _pendingDeepLink;

  // Canal Android haute priorité
  static const _channel = AndroidNotificationChannel(
    'pronowin_high',
    'PronoWin Notifications',
    description: 'Notifications PronoWin importantes',
    importance:  Importance.high,
    playSound:   true,
    enableVibration: true,
  );

  /// Appeler une seule fois au démarrage de l'app
  static Future<void> init({required WidgetRef ref}) async {

    // 1. Demander la permission
    final settings = await _fcm.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Permission refusée');
      return;
    }

    // Sur iPhone, une notification reçue app ouverte n'est affichée par iOS
    // que si on le lui demande. Sans ces options, rien ne s'affichait : la
    // copie locale d'Android dépend là-bas d'un délégué que l'app ne déclare
    // pas.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }

    // 2. Configurer les notifications locales (foreground)
    const initSettings = InitializationSettings(
      // `@mipmap/ic_launcher` etait le logo Flutter par defaut, jamais
      // remplace : l'application utilise `launcher_icon`. Et une icone de
      // notification doit etre monochrome — Android n'en garde que l'alpha.
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS:     DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Tap sur une notification locale (app en foreground)
        debugPrint('[FCM Local tap] payload: ${details.payload}');
        _navigate(details.payload);
      },
    );

    // 3. Créer le canal Android
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Capturer le notifier pour les mises à jour temps réel
    final notifier = ref.read(notificationNotifierProvider.notifier);

    // 4. Notifications en foreground → afficher localement + injecter dans le state
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM Foreground] ${message.notification?.title}');
      if (copieLocale()) _showLocal(message);
      // ✅ Mise à jour temps réel du badge et de la liste
      notifier.pushIncoming(remoteMessageToNotification(message));
    });

    // 5. Tap notification (app en background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final link = message.data['deep_link'] as String?;
      AnalyseUsage.notificationOuverte((message.data['type'] as String?) ?? '');
      debugPrint('[FCM Tap background→foreground] deep_link: $link');
      // Rafraîchir la liste depuis l'API (la notif est déjà en base)
      notifier.fetch();
      _navigate(link);
    });

    // 6. App lancée depuis une notification (app était tuée)
    //    → stocker le lien et naviguer après init du router
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      final link = initial.data['deep_link'] as String?;
      debugPrint('[FCM App killed → opened] deep_link: $link');
      if (link != null && link.isNotEmpty) {
        // Attendre que le router soit prêt (frame suivante)
        _pendingDeepLink = link;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _flushPendingDeepLink();
        });
      }
    }

    // 7. Enregistrer le token FCM sur le backend — inutile (et rejeté par
    //    l'API) tant qu'on navigue en invité, sans compte.
    if (ref.read(effectiveLoggedInProvider)) {
      final token = await jetonFcm();
      if (token != null) {
        debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
        await _registerToken(ref, token);
      }
    }

    // 8. Écouter les refreshes de token — uniquement utile pour un compte connecté
    _fcm.onTokenRefresh.listen((newToken) {
      if (!ref.read(effectiveLoggedInProvider)) return;
      debugPrint('[FCM] Token refresh');
      _registerToken(ref, newToken);
    });

    debugPrint('[FCM] ✅ Initialisé avec succès');
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// Naviguer vers un deep link via le context du navigator racine.
  static void _navigate(String? deepLink) {
    if (deepLink == null || deepLink.isEmpty) return;
    debugPrint('[FCM] Navigating to: $deepLink');

    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('[FCM] Context non dispo — mise en attente');
      _pendingDeepLink = deepLink;
      return;
    }
    try {
      context.go(deepLink);
    } catch (e) {
      debugPrint('[FCM] Erreur navigation: $e');
    }
  }

  /// Appelée après init pour naviguer si un deep link était en attente.
  static void _flushPendingDeepLink() {
    final link = _pendingDeepLink;
    if (link == null) return;
    _pendingDeepLink = null;
    _navigate(link);
  }

  /// Méthode publique — appeler depuis main.dart après init du router
  /// pour consommer un éventuel deep link d'app tuée.
  static void consumePendingDeepLink() => _flushPendingDeepLink();

  // ── Notifications locales (foreground) ────────────────────────────────────

  /// Une notification reçue app ouverte est recopiée en notification locale
  /// sur Android seulement : sur iPhone, iOS l'affiche déjà (options de
  /// présentation au premier plan), et une copie ferait doublon.
  @visibleForTesting
  static bool copieLocale() => defaultTargetPlatform != TargetPlatform.iOS;

  static Future<void> _showLocal(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;

    final deepLink = message.data['deep_link'] as String?;

    await _local.show(
      message.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance:   Importance.high,
          priority:     Priority.high,
          icon:         '@mipmap/launcher_icon',
          styleInformation: BigTextStyleInformation(notif.body ?? ''),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: deepLink,
    );
  }

  // ── Token backend ──────────────────────────────────────────────────────────

  static Future<void> _registerToken(WidgetRef ref, String token) async {
    try {
      await ref.read(dioProvider).post('/notifications/register-token', data: {
        'fcm_token': token,
        'language': AppStrings.current.locale.languageCode,
        // « android » était écrit en dur : chaque iPhone était enregistré
        // comme un Android.
        'platform':  plateforme(),
      });
      debugPrint('[FCM] Token enregistré sur le backend ✅');
    } catch (e) {
      debugPrint('[FCM] Erreur enregistrement token: $e');
    }
  }

  /// Le jeton de cet appareil (la déconnexion le transmet au serveur).
  static Future<String?> getToken() => jetonFcm();

  /// La plateforme annoncée au serveur avec le jeton.
  @visibleForTesting
  static String plateforme() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Le jeton Firebase de cet appareil, ou `null` s'il n'est pas encore là.
  ///
  /// Sur iPhone, Firebase ne délivre son jeton qu'après avoir reçu celui
  /// d'Apple (APNs), qui arrive quelques instants après le lancement. Le
  /// demander avant lève `apns-token-not-set` : rien ne l'attrapait, et
  /// `init()` s'arrêtait avant d'écouter les renouvellements — le téléphone
  /// ne s'enregistrait jamais. On attend le jeton APNs quelques secondes ;
  /// s'il ne vient pas, `onTokenRefresh` livrera le jeton Firebase plus tard.
  static Future<String?> jetonFcm() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await attendreValeur(_fcm.getAPNSToken);
        if (apns == null) {
          debugPrint('[FCM] Jeton APNs pas encore reçu — enregistrement au prochain renouvellement');
          return null;
        }
      }
      return await _fcm.getToken();
    } catch (e) {
      // Une notification manquée ne doit jamais interrompre le démarrage.
      debugPrint('[FCM] Jeton indisponible : $e');
      return null;
    }
  }

  /// Relit [lire] jusqu'à obtenir une valeur, au plus [tentatives] fois.
  @visibleForTesting
  static Future<String?> attendreValeur(
    Future<String?> Function() lire, {
    int tentatives = 10,
    Duration pause = const Duration(milliseconds: 500),
  }) async {
    for (var i = 0; i < tentatives; i++) {
      final valeur = await lire();
      if (valeur != null) return valeur;
      if (i < tentatives - 1) await Future<void>.delayed(pause);
    }
    return null;
  }

  /// À appeler juste après une connexion réussie (un invité vient de créer
  /// un compte / se connecter) pour rattacher le token FCM déjà obtenu.
  static Future<void> registerCurrentToken(WidgetRef ref) async {
    final token = await jetonFcm();
    if (token != null) await _registerToken(ref, token);
  }
}
