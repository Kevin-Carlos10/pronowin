import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('parse un objet complet correctement', () {
      final json = {
        'id': 'notif-123',
        'title': 'PronoWin',
        'body': 'Votre pronostic a gagné !',
        'type': 'match',
        'is_read': false,
        'created_at': '2026-06-27T10:00:00.000Z',
        'deep_link': '/pronostics/abc',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 'notif-123');
      expect(notif.title, 'PronoWin');
      expect(notif.body, 'Votre pronostic a gagné !');
      expect(notif.type, NotificationType.match);
      expect(notif.isRead, false);
      expect(notif.deepLink, '/pronostics/abc');
      expect(notif.createdAt.year, 2026);
    });

    test('utilise des valeurs par défaut si des champs sont absents', () {
      final json = {
        'id': 'notif-456',
        'title': 'Test',
        'body': 'Corps',
        'created_at': '2026-06-27T10:00:00.000Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.type, NotificationType.system);
      expect(notif.isRead, false);
      expect(notif.deepLink, isNull);
    });

    test('parse correctement tous les types de notification', () {
      for (final entry in {
        'match': NotificationType.match,
        'promo': NotificationType.promo,
        'payment': NotificationType.payment,
        'referral': NotificationType.referral,
        'system': NotificationType.system,
        'unknown': NotificationType.system,
      }.entries) {
        final notif = AppNotification.fromJson({
          'id': 'x',
          'title': 'T',
          'body': 'B',
          'type': entry.key,
          'created_at': '2026-06-27T10:00:00.000Z',
        });
        expect(notif.type, entry.value,
            reason: 'type "${entry.key}" devrait mapper sur ${entry.value}');
      }
    });

    test('copyWith ne modifie que isRead', () {
      final original = AppNotification.fromJson({
        'id': 'n1',
        'title': 'Titre',
        'body': 'Corps',
        'is_read': false,
        'created_at': '2026-06-27T10:00:00.000Z',
      });

      final copy = original.copyWith(isRead: true);

      expect(copy.isRead, true);
      expect(copy.id, original.id);
      expect(copy.title, original.title);
    });

    test('created_at invalide utilise DateTime.now() comme fallback', () {
      final before = DateTime.now();
      final notif = AppNotification.fromJson({
        'id': 'n2',
        'title': 'T',
        'body': 'B',
        'created_at': 'date-invalide',
      });
      final after = DateTime.now();

      expect(notif.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(notif.createdAt.isBefore(after.add(const Duration(seconds: 1))), true);
    });
  });
}
