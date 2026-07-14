import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/referral_entity.dart';

abstract class ReferralRepository {
  Future<Either<Failure, ReferralStatsEntity>> getStats();
  Future<Either<Failure, List<ReferralEntity>>> getReferrals({int page});
  Future<Either<Failure, void>> withdrawEarnings(double amount, String phoneNumber);
}
