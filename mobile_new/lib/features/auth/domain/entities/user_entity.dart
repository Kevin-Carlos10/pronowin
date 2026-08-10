import 'package:equatable/equatable.dart';

enum SubscriptionPlan { free, premium }

class UserEntity extends Equatable {
  final String id;
  final String? phoneNumber;
  final String? email;
  final String pseudo;
  final String? firstName;
  final String? lastName;
  final DateTime? birthDate;
  final String? avatarUrl;
  final String countryCode;
  final SubscriptionPlan subscriptionPlan;
  final DateTime? subscriptionExpiresAt;
  final String referralCode;
  final double referralEarnings;
  final DateTime createdAt;
  final DateTime? acceptedTermsAt;
  final bool phoneVerified;
  final bool emailVerified;

  const UserEntity({
    required this.id,
    this.phoneNumber,
    this.email,
    required this.pseudo,
    this.firstName,
    this.lastName,
    this.birthDate,
    this.avatarUrl,
    required this.countryCode,
    required this.subscriptionPlan,
    this.subscriptionExpiresAt,
    required this.referralCode,
    required this.referralEarnings,
    required this.createdAt,
    this.acceptedTermsAt,
    this.phoneVerified = false,
    this.emailVerified = false,
  });

  // Premium si le plan est premium ET (pas de date d'expiration = permanent, ou date future)
  bool get isPremium =>
      subscriptionPlan == SubscriptionPlan.premium &&
      (subscriptionExpiresAt == null || subscriptionExpiresAt!.isAfter(DateTime.now()));

  // Vrai si les infos essentielles (nom, prénom, date de naissance, téléphone) sont renseignées
  bool get isProfileComplete =>
      (firstName?.isNotEmpty ?? false) &&
      (lastName?.isNotEmpty ?? false) &&
      birthDate != null &&
      (phoneNumber?.isNotEmpty ?? false);

  // Nom à afficher : prénom si dispo, sinon pseudo
  String get displayName {
    if (firstName != null && firstName!.isNotEmpty) return firstName!;
    return pseudo;
  }

  @override
  List<Object?> get props => [id, phoneNumber, pseudo, subscriptionPlan, phoneVerified, emailVerified];
}
