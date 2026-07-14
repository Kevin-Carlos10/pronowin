import 'package:equatable/equatable.dart';

enum ReferralStatus { pending, active, rewarded }

class ReferralEntity extends Equatable {
  final String id;
  final String referredUserPseudo;
  final String? referredUserAvatar;
  final int    level;          // 1 ou 2
  final double commissionAmount;
  final ReferralStatus status;
  final DateTime joinedAt;

  const ReferralEntity({
    required this.id, required this.referredUserPseudo,
    this.referredUserAvatar, required this.level,
    required this.commissionAmount, required this.status,
    required this.joinedAt,
  });

  bool get isRewarded => status == ReferralStatus.rewarded;

  @override
  List<Object?> get props => [id];
}

class ReferralStatsEntity extends Equatable {
  final String referralCode;
  final int    totalReferrals;
  final int    activeReferrals;
  final int    pendingReferrals;
  final double totalEarnings;
  final double pendingEarnings;
  final double withdrawableEarnings;
  final List<ReferralEntity> recentReferrals;

  const ReferralStatsEntity({
    required this.referralCode,
    required this.totalReferrals,
    required this.activeReferrals,
    required this.pendingReferrals,
    required this.totalEarnings,
    required this.pendingEarnings,
    required this.withdrawableEarnings,
    required this.recentReferrals,
  });

  bool get canWithdraw => withdrawableEarnings >= 2000;

  @override
  List<Object?> get props => [referralCode];
}
