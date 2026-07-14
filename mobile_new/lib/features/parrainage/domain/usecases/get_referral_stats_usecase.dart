import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/referral_entity.dart';
import '../repositories/referral_repository.dart';

class GetReferralStatsUseCase {
  final ReferralRepository _repo;
  GetReferralStatsUseCase(this._repo);
  Future<Either<Failure, ReferralStatsEntity>> call() => _repo.getStats();
}
