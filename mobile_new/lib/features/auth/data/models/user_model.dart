import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    super.phoneNumber,
    super.email,
    required super.pseudo,
    super.firstName,
    super.lastName,
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
    avatarUrl:     json['avatar_url'] as String?,
    countryCode:   json['country_code'] as String? ?? 'BF',
    subscriptionPlan: json['subscription_plan'] == 'premium'
        ? SubscriptionPlan.premium
        : SubscriptionPlan.free,
    subscriptionExpiresAt: json['subscription_expires_at'] != null
        ? DateTime.parse(json['subscription_expires_at'] as String)
        : null,
    referralCode:     json['referral_code'] as String? ?? '',
    referralEarnings: (json['referral_earnings'] as num?)?.toDouble() ?? 0.0,
    createdAt:        DateTime.parse(json['created_at'] as String),
    acceptedTermsAt:  json['accepted_terms_at'] != null
        ? DateTime.parse(json['accepted_terms_at'] as String)
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
