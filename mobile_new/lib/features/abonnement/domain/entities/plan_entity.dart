import 'package:equatable/equatable.dart';

enum PlanType { free, premium }

class PlanEntity extends Equatable {
  final String id;
  final PlanType type;
  final String name;
  final String description;
  final double price;
  final String currency;
  final int durationDays;
  final List<String> features;
  final List<String> lockedFeatures;
  final bool isPopular;

  const PlanEntity({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.features,
    required this.lockedFeatures,
    required this.isPopular,
  });

  bool get isFree    => type == PlanType.free;
  bool get isPremium => type == PlanType.premium;

  String get priceLabel =>
      isFree ? 'Gratuit' : '${price.toStringAsFixed(0)} $currency / mois';

  @override
  List<Object?> get props => [id];
}

class SubscriptionEntity extends Equatable {
  final String id;
  final PlanType plan;
  final DateTime startDate;
  final DateTime endDate;
  final String paymentMethod;
  final String? promoCodeUsed;
  final bool autoRenew;
  final bool isActive;

  const SubscriptionEntity({
    required this.id,
    required this.plan,
    required this.startDate,
    required this.endDate,
    required this.paymentMethod,
    this.promoCodeUsed,
    required this.autoRenew,
    required this.isActive,
  });

  bool get isExpired => endDate.isBefore(DateTime.now());
  int  get daysLeft  => endDate.difference(DateTime.now()).inDays.clamp(0, 9999);

  @override
  List<Object?> get props => [id];
}

class PromoCodeEntity extends Equatable {
  final String code;
  final bool   isValid;
  final int    durationDays;
  final String description;

  const PromoCodeEntity({
    required this.code,
    required this.isValid,
    required this.durationDays,
    required this.description,
  });

  @override
  List<Object?> get props => [code];
}
