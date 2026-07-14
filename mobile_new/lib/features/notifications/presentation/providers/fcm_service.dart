import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/navigation_keys.dart';
import 'notification_service.dart';

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

    // 2. Configurer les notifications locales (foreground)
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
      _showLocal(message);
      // ✅ Mise à jour temps réel du badge et de la liste
      notifier.pushIncoming(remoteMessageToNotification(message));
    });

    // 5. Tap notification (app en background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final link = message.data['deep_link'] as String?;
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

    // 7. Enregistrer le token FCM sur le backend
    final token = await _fcm.getToken();
    if (token != null) {
      debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
      await _registerToken(ref, token);
    }

    // 8. Écouter les refreshes de token
    _fcm.onTokenRefresh.listen((newToken) {
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
        'platform':  'android',
      });
      debugPrint('[FCM] Token enregistré sur le backend ✅');
    } catch (e) {
      debugPrint('[FCM] Erreur enregistrement token: $e');
    }
  }

  /// Récupérer le token actuel (utile pour debug)
  static Future<String?> getToken() => _fcm.getToken();
}
