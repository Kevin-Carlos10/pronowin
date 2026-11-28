import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ce que le téléphone permet à l'application.
enum EtatNotifications {
  autorisees,
  refusees,
  /// La question n'a jamais été posée (iPhone, Android 13 et plus).
  aDemander,
  /// Impossible à savoir (web, Firebase indisponible).
  inconnu,
}

/// Les notifications au niveau du téléphone, et ses réglages.
///
/// Repris de Sofascore (vidéos du 8 novembre 2026) : quand on suit un match
/// alors que les notifications de l'application sont coupées dans les
/// réglages du téléphone, Sofascore le dit et propose d'aller les rouvrir.
/// PronoWin acceptait le suivi et annonçait « tu recevras le coup d'envoi,
/// les buts et le résultat » — qui n'arrivaient jamais.
class ReglagesSysteme {
  ReglagesSysteme._();

  /// L'état détaillé. Remplaçable pour les tests.
  static Future<EtatNotifications> Function() lireEtat = _lireEtat;

  /// Pose la question du téléphone ; vrai si la réponse est oui.
  /// Remplaçable pour les tests.
  static Future<bool> Function() demander = _demander;

  static Future<EtatNotifications> _lireEtat() async {
    if (kIsWeb) return EtatNotifications.inconnu;
    try {
      final r = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (r.authorizationStatus) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => EtatNotifications.autorisees,
        AuthorizationStatus.denied => EtatNotifications.refusees,
        AuthorizationStatus.notDetermined => EtatNotifications.aDemander,
      };
    } catch (_) {
      return EtatNotifications.inconnu;
    }
  }

  static Future<bool> _demander() async {
    try {
      final r = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      }
      return r.authorizationStatus == AuthorizationStatus.authorized
          || r.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  static const _canal = MethodChannel('com.pronowin.app/reglages');

  /// Les notifications sont-elles permises ? null : on ne sait pas (web,
  /// Firebase indisponible) — dans le doute, on ne dit rien.
  ///
  /// Remplaçable pour les tests.
  static Future<bool?> Function() lireAutorisation = () async => switch (await lireEtat()) {
    EtatNotifications.autorisees => true,
    EtatNotifications.refusees => false,
    // Jamais demandé (iPhone) ou inconnu : rien à signaler.
    _ => null,
  };

  /// Ouvre les réglages de notifications de l'application. Remplaçable pour
  /// les tests.
  static Future<void> Function() ouvrirNotifications = _ouvrir;

  static Future<void> _ouvrir() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android : directement la page « Notifications » de l'application
      // (MainActivity.kt).
      try {
        await _canal.invokeMethod<void>('ouvrirNotifications');
        return;
      } catch (_) {
        // Version de l'application sans le canal : rien de mieux à faire.
        return;
      }
    }
    // iPhone : la page de l'application dans Réglages, où se trouvent ses
    // notifications.
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {}
  }
}
