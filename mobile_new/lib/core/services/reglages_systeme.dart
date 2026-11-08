import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Les notifications au niveau du téléphone, et ses réglages.
///
/// Repris de Sofascore (vidéos du 8 novembre 2026) : quand on suit un match
/// alors que les notifications de l'application sont coupées dans les
/// réglages du téléphone, Sofascore le dit et propose d'aller les rouvrir.
/// PronoWin acceptait le suivi et annonçait « tu recevras le coup d'envoi,
/// les buts et le résultat » — qui n'arrivaient jamais.
class ReglagesSysteme {
  ReglagesSysteme._();

  static const _canal = MethodChannel('com.pronowin.app/reglages');

  /// Les notifications sont-elles permises ? null : on ne sait pas (web,
  /// Firebase indisponible) — dans le doute, on ne dit rien.
  ///
  /// Remplaçable pour les tests.
  static Future<bool?> Function() lireAutorisation = _lire;

  /// Ouvre les réglages de notifications de l'application. Remplaçable pour
  /// les tests.
  static Future<void> Function() ouvrirNotifications = _ouvrir;

  static Future<bool?> _lire() async {
    if (kIsWeb) return null;
    try {
      final r = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (r.authorizationStatus) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => true,
        AuthorizationStatus.denied => false,
        // Jamais demandé (iPhone) : la question sera posée au prochain
        // démarrage, rien à signaler.
        AuthorizationStatus.notDetermined => null,
      };
    } catch (_) {
      return null;
    }
  }

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
