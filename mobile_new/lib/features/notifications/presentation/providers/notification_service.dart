import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';

// ─── Modèle ───────────────────────────────────────────────────────────────────
class AppNotification {
  final String           id;
  final String           title;
  final String           body;
  final NotificationType type;
  final bool             isRead;
  final DateTime         createdAt;
  final String?          deepLink;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.deepLink,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id:        j['id']        as String,
    title:     j['title']     as String,
    body:      j['body']      as String,
    type:      _typeFromString(j['type'] as String? ?? 'system'),
    isRead:    j['is_read']   as bool?   ?? false,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal()
               ?? DateTime.now(),
    deepLink:  j['deep_link'] as String?,
  );

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id, title: title, body: body, type: type,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt, deepLink: deepLink,
  );

  static NotificationType _typeFromString(String s) => typeFromString(s);

  static NotificationType typeFromString(String s) => switch (s) {
    'match'    => NotificationType.match,
    'promo'    => NotificationType.promo,
    'payment'  => NotificationType.payment,
    'referral' => NotificationType.referral,
    _          => NotificationType.system,
  };
}

enum NotificationType { match, promo, system, payment, referral }

// ─── Notifier avec API ────────────────────────────────────────────────────────
class NotificationNotifier
    extends StateNotifier<AsyncValue<List<AppNotification>>> {
  final Dio _dio;

  NotificationNotifier(this._dio) : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final r    = await _dio.get('/notifications/my');
      final list = (r.data as List<dynamic>)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// Injecte une notification FCM reçue en temps réel (foreground)
  /// sans attendre un rechargement complet depuis l'API.
  void pushIncoming(AppNotification notif) {
    // Éviter les doublons (même id)
    final current = state.valueOrNull ?? [];
    if (current.any((n) => n.id == notif.id)) return;
    state = AsyncValue.data([notif, ...current]);
  }

  Future<void> markRead(String id) async {
    state = state.whenData(
      (l) => l.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(),
    );
    try { await _dio.patch('/notifications/$id/read'); } catch (_) {}
  }

  Future<void> markAllRead() async {
    state = state.whenData(
      (l) => l.map((n) => n.copyWith(isRead: true)).toList(),
    );
    try { await _dio.post('/notifications/mark-all-read'); } catch (_) {}
  }
}


// ─── Helper : convertir RemoteMessage → AppNotification ──────────────────────
AppNotification remoteMessageToNotification(RemoteMessage message) {
  final data = message.data;
  return AppNotification(
    id:        message.messageId
               ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title:     message.notification?.title ?? 'PronoWin',
    body:      message.notification?.body  ?? '',
    type:      AppNotification.typeFromString(
                 data['type'] as String? ?? 'system'),
    isRead:    false,
    createdAt: DateTime.now(),
    deepLink:  data['deep_link'] as String?,
  );
}

// ─── Providers ────────────────────────────────────────────────────────────────
final notificationNotifierProvider = StateNotifierProvider<
    NotificationNotifier, AsyncValue<List<AppNotification>>>(
  (ref) => NotificationNotifier(ref.read(dioProvider)),
);

/// Liste plate (rétrocompatible avec la page)
final notificationProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationNotifierProvider).maybeWhen(
    data:   (list) => list,
    orElse: () => [],
  );
});

/// Nombre de non-lus
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationProvider).where((n) => !n.isRead).length,
);

/// Filtre actif sur le type (null = tous)
final notifTypeFilterProvider = StateProvider<NotificationType?>((ref) => null);

/// Liste filtrée selon le filtre actif
final filteredNotifProvider = Provider<List<AppNotification>>((ref) {
  final all    = ref.watch(notificationProvider);
  final filter = ref.watch(notifTypeFilterProvider);
  if (filter == null) return all;
  return all.where((n) => n.type == filter).toList();
});
