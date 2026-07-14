import 'package:equatable/equatable.dart';

enum NotificationType { match, promo, system, payment, referral }

class AppNotificationEntity extends Equatable {
  final String           id;
  final String           title;
  final String           body;
  final NotificationType type;
  final bool             isRead;
  final String?          deepLink;
  final Map<String, dynamic>? payload;
  final DateTime         createdAt;

  const AppNotificationEntity({
    required this.id, required this.title, required this.body,
    required this.type, required this.isRead, this.deepLink,
    this.payload, required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
