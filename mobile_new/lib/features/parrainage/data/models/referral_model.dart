import '../../domain/entities/referral_entity.dart';

class ReferralModel extends ReferralEntity {
  const ReferralModel({
    required super.id, required super.referredUserPseudo,
    super.referredUserAvatar, required super.level,
    required super.commissionAmount, required super.status, required super.joinedAt,
  });

  factory ReferralModel.fromJson(Map<String, dynamic> j) => ReferralModel(
    id:                   j['id'] as String,
    referredUserPseudo:   j['referred_user_pseudo'] as String? ?? 'Utilisateur',
    referredUserAvatar:   j['referred_user_avatar'] as String?,
    level:                j['level'] as int? ?? 1,
    commissionAmount:     (j['commission_amount'] as num?)?.toDouble() ?? 0,
    status:               _parseStatus(j['status'] as String?),
    joinedAt:             DateTime.parse(j['joined_at'] as String),
  );

  static ReferralStatus _parseStatus(String? s) => switch (s) {
    'rewarded' => ReferralStatus.rewarded,
    'active'   => ReferralStatus.active,
    _          => ReferralStatus.pending,
  };
}

class ReferralStatsModel extends ReferralStatsEntity {
  const ReferralStatsModel({
    required super.referralCode, required super.totalReferrals,
    required super.activeReferrals, required super.pendingReferrals,
    required super.totalEarnings, required super.pendingEarnings,
    required super.withdrawableEarnings, required super.recentReferrals,
  });

  factory ReferralStatsModel.fromJson(Map<String, dynamic> j) => ReferralStatsModel(
    referralCode:         j['referral_code'] as String,
    totalReferrals:       j['total_referrals'] as int? ?? 0,
    activeReferrals:      j['active_referrals'] as int? ?? 0,
    pendingReferrals:     j['pending_referrals'] as int? ?? 0,
    totalEarnings:        (j['total_earnings'] as num?)?.toDouble() ?? 0,
    pendingEarnings:      (j['pending_earnings'] as num?)?.toDouble() ?? 0,
    withdrawableEarnings: (j['withdrawable_earnings'] as num?)?.toDouble() ?? 0,
    recentReferrals:      (j['recent_referrals'] as List? ?? [])
        .map((e) => ReferralModel.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
