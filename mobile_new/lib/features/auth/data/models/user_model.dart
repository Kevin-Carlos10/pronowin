import '../../domain/entities/user_entity.dart';

/// Tout le profil, au format de l'API : [UserModel.fromJson] le relit tel
/// quel. Sert au profil gardé sur l'appareil (`AuthRepository.memoriserProfil`).
Map<String, dynamic> profilVersJson(UserEntity u) => {
  'id':                      u.id,
  'phone_number':            u.phoneNumber,
  'email':                   u.email,
  'pseudo':                  u.pseudo,
  'first_name':              u.firstName,
  'last_name':               u.lastName,
  'birth_date':              u.birthDate?.toIso8601String(),
  'avatar_url':              u.avatarUrl,
  'country_code':            u.countryCode,
  'subscription_plan':       u.subscriptionPlan.name,
  'subscription_expires_at': u.subscriptionExpiresAt?.toUtc().toIso8601String(),
  'referral_code':           u.referralCode,
  'referral_earnings':       u.referralEarnings,
  'created_at':              u.createdAt.toUtc().toIso8601String(),
  'accepted_terms_at':       u.acceptedTermsAt?.toUtc().toIso8601String(),
  'phone_verified':          u.phoneVerified,
  'email_verified':          u.emailVerified,
};

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    super.phoneNumber,
    super.email,
    required super.pseudo,
    super.firstName,
    super.lastName,
    super.birthDate,
    super.avatarUrl,
    required super.countryCode,
    required super.subscriptionPlan,
    super.subscriptionExpiresAt,
    required super.referralCode,
    required super.referralEarnings,
    required super.createdAt,
    super.acceptedTermsAt,
    super.phoneVerified,
    super.emailVerified,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:            json['id'] as String,
    phoneNumber:   json['phone_number'] as String?,
    email:         json['email'] as String?,
    pseudo:        json['pseudo'] as String? ?? 'Utilisateur',
    firstName:     json['first_name'] as String?,
    lastName:      json['last_name'] as String?,
    birthDate:     json['birth_date'] != null
        ? DateTime.tryParse(json['birth_date'] as String)
        : null,
    avatarUrl:     json['avatar_url'] as String?,
    countryCode:   json['country_code'] as String? ?? 'BF',
    subscriptionPlan: json['subscription_plan'] == 'premium'
        ? SubscriptionPlan.premium
        : SubscriptionPlan.free,
    subscriptionExpiresAt: json['subscription_expires_at'] != null
        ? DateTime.parse(json['subscription_expires_at'] as String).toLocal()
        : null,
    referralCode:     json['referral_code'] as String? ?? '',
    referralEarnings: (json['referral_earnings'] as num?)?.toDouble() ?? 0.0,
    createdAt:        DateTime.parse(json['created_at'] as String).toLocal(),
    acceptedTermsAt:  json['accepted_terms_at'] != null
        ? DateTime.parse(json['accepted_terms_at'] as String).toLocal()
        : null,
    phoneVerified:  json['phone_verified'] as bool? ?? false,
    emailVerified:  json['email_verified'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':           id,
    'phone_number': phoneNumber,
    'email':        email,
    'pseudo':       pseudo,
    'avatar_url':   avatarUrl,
    'country_code': countryCode,
    'subscription_plan': subscriptionPlan.name,
    'subscription_expires_at': subscriptionExpiresAt?.toIso8601String(),
    'referral_code':     referralCode,
    'referral_earnings': referralEarnings,
    'created_at':  createdAt.toIso8601String(),
  };
}
