import '../../domain/entities/plan_entity.dart';

class PlanModel extends PlanEntity {
  const PlanModel({
    required super.id, required super.type, required super.name,
    required super.description, required super.price, required super.currency,
    required super.durationDays, required super.features,
    required super.lockedFeatures, required super.isPopular,
  });

  factory PlanModel.fromJson(Map<String, dynamic> j) => PlanModel(
    id:            j['id'] as String,
    type:          j['type'] == 'premium' ? PlanType.premium : PlanType.free,
    name:          j['name'] as String,
    description:   j['description'] as String? ?? '',
    price:         (j['price'] as num?)?.toDouble() ?? 0,
    currency:      j['currency'] as String? ?? 'FCFA',
    durationDays:  j['duration_days'] as int? ?? 30,
    features:      List<String>.from(j['features'] as List? ?? []),
    lockedFeatures:List<String>.from(j['locked_features'] as List? ?? []),
    isPopular:     j['is_popular'] as bool? ?? false,
  );
}

class SubscriptionModel extends SubscriptionEntity {
  const SubscriptionModel({
    required super.id, required super.plan, required super.startDate,
    required super.endDate, required super.paymentMethod,
    super.promoCodeUsed, required super.autoRenew, required super.isActive,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> j) => SubscriptionModel(
    id:            j['id'] as String,
    plan:          j['plan'] == 'premium' ? PlanType.premium : PlanType.free,
    startDate:     DateTime.parse(j['start_date'] as String),
    endDate:       DateTime.parse(j['end_date'] as String),
    paymentMethod: j['payment_method'] as String? ?? '',
    promoCodeUsed: j['promo_code_used'] as String?,
    autoRenew:     j['auto_renew'] as bool? ?? false,
    isActive:      j['is_active'] as bool? ?? false,
  );
}

class PromoCodeModel extends PromoCodeEntity {
  const PromoCodeModel({
    required super.code, required super.isValid,
    required super.durationDays, required super.description,
  });

  factory PromoCodeModel.fromJson(Map<String, dynamic> j) => PromoCodeModel(
    code:         j['code'] as String,
    isValid:      j['is_valid'] as bool? ?? false,
    durationDays: j['duration_days'] as int? ?? 30,
    description:  j['description'] as String? ?? '',
  );
}
