import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/features/notifications/presentation/providers/fcm_service.dart';

/// Le jeton de notification sur iPhone.
///
/// Firebase n'y délivre son jeton qu'après celui d'Apple (APNs). Demandé trop
/// tôt, il levait une erreur que rien n'attrapait : le démarrage des
/// notifications s'arrêtait, et le téléphone ne s'enregistrait jamais. Et
/// chaque iPhone était annoncé au serveur comme un Android.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('un iPhone s\'annonce comme tel au serveur', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(FCMService.plateforme(), 'ios');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(FCMService.plateforme(), 'android');
  });

  test('app ouverte : iOS affiche la notification lui-même, Android par une copie locale', () {
    // Sans les options de présentation, un iPhone app ouverte n'affichait
    // rien ; avec elles, une copie locale en plus ferait doublon.
    final source = File('lib/features/notifications/presentation/providers/fcm_service.dart').readAsStringSync();
    expect(source, matches(RegExp(
        r'setForegroundNotificationPresentationOptions\(\s*alert: true, badge: true, sound: true\)')));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(FCMService.copieLocale(), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(FCMService.copieLocale(), isTrue);
  });

  test('le jeton APNs arrivé après quelques essais est attendu', () async {
    var essais = 0;
    final v = await FCMService.attendreValeur(() async => ++essais < 3 ? null : 'apns',
        pause: Duration.zero);
    expect(v, 'apns');
    expect(essais, 3);
  });

  test('sans jeton APNs, on abandonne sans erreur, après le nombre d\'essais prévu', () async {
    var essais = 0;
    final v = await FCMService.attendreValeur(() async { essais++; return null; },
        tentatives: 4, pause: Duration.zero);
    expect(v, isNull);
    expect(essais, 4);
  });
}
