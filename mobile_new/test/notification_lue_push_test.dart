import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/notifications/presentation/providers/fcm_service.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';

/// Une notification ouverte depuis l'écran du téléphone est lue (25 octobre
/// 2026).
///
/// Seul le toucher dans la liste de l'application la marquait : le compteur
/// restait allumé pour des notifications déjà ouvertes, et la part « lue »
/// du tableau de bord était sous-estimée. Le serveur glisse désormais
/// l'identifiant de la notification enregistrée dans la push.
class _Serveur implements HttpClientAdapter {
  final requetes = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    requetes.add('${o.method} ${o.path}');
    final corps = o.path == '/notifications/my'
        ? jsonEncode([
            {'id': 'n1', 'title': 'But pour Arsenal !', 'body': '1-0', 'type': 'match', 'is_read': false,
             'created_at': '2026-10-25T15:00:00Z', 'deep_link': '/pronostics/p1'},
          ])
        : jsonEncode({'success': true});
    return ResponseBody.fromString(corps, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// La liste chargée depuis le faux serveur.
Future<void> _charge(NotificationNotifier n) async {
  for (var i = 0; i < 100 && n.state.value == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('la notification locale porte le lien et l\'identifiant ; une ancienne, le lien seul', () {
    final charge = FCMService.chargeDe({'deep_link': '/pronostics/p1', 'notification_id': 'n1', 'type': 'match'});
    expect(FCMService.lireCharge(charge), (lien: '/pronostics/p1', id: 'n1'));
    expect(FCMService.lireCharge('/historique'), (lien: '/historique', id: null));
    expect(FCMService.lireCharge(null), (lien: null, id: null));
    expect(FCMService.lireCharge('{pas du json'), (lien: null, id: null));
  });

  test('une push reçue app ouverte prend l\'identifiant du serveur', () {
    final n = remoteMessageToNotification(const RemoteMessage(
      messageId: 'fcm-123',
      data: {'notification_id': 'n1', 'type': 'match', 'title_fr': 'But pour Arsenal !', 'body_fr': '1-0'},
    ));
    expect(n.id, 'n1');
    expect(remoteMessageToNotification(const RemoteMessage(messageId: 'fcm-123', data: {'type': 'match'})).id,
      'fcm-123', reason: 'sans identifiant (campagne, serveur plus ancien) : celui de FCM, comme avant');
  });

  test('ouverte depuis l\'écran du téléphone : lue sur le serveur, et le compteur baisse', () async {
    final serveur = _Serveur();
    final notifier = NotificationNotifier(Dio(BaseOptions(baseUrl: 'https://banc'))..httpClientAdapter = serveur);
    await _charge(notifier);
    expect(notifier.state.value!.where((n) => !n.isRead), hasLength(1));

    await marquerLueDepuisPush(notifier, {'notification_id': 'n1', 'deep_link': '/pronostics/p1'});
    expect(serveur.requetes, contains('PATCH /notifications/n1/read'));
    expect(notifier.state.value!.where((n) => !n.isRead), isEmpty);
  });

  test('sans identifiant, rien n\'est envoyé', () async {
    final serveur = _Serveur();
    final notifier = NotificationNotifier(Dio(BaseOptions(baseUrl: 'https://banc'))..httpClientAdapter = serveur);
    await _charge(notifier);
    await marquerLueDepuisPush(notifier, {'deep_link': '/pronostics/p1'});
    await marquerLueDepuisPush(notifier, {'notification_id': ''});
    expect(serveur.requetes.where((r) => r.startsWith('PATCH')), isEmpty);
  });
}
