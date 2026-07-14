import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../../domain/entities/referral_entity.dart';
import '../../domain/repositories/referral_repository.dart';
import '../datasources/referral_remote_datasource.dart';

class ReferralRepositoryImpl implements ReferralRepository {
  final ReferralRemoteDataSource _remote;
  ReferralRepositoryImpl(this._remote);

  @override Future<Either<Failure, ReferralStatsEntity>> getStats() async {
    try { return Right(await _remote.getStats()); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, List<ReferralEntity>>> getReferrals({int page = 1}) async {
    try { return Right(await _remote.getReferrals(page: page)); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, void>> withdrawEarnings(double amount, String phone) async {
    try { await _remote.withdrawEarnings(amount, phone); return const Right(null); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
}
