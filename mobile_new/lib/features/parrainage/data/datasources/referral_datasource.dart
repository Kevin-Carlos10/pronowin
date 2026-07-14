import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../models/referral_model.dart';

abstract class ReferralDataSource {
  Future<ReferralStatsModel> getStats();
  Future<void>               withdrawEarnings(double amount, String phoneNumber);
}

class ReferralDataSourceImpl implements ReferralDataSource {
  final Dio _dio;
  ReferralDataSourceImpl(this._dio);

  @override
  Future<ReferralStatsModel> getStats() async {
    try {
      final r = await _dio.get(ApiEndpoints.referral);
      return ReferralStatsModel.fromJson(r.data as Map<String,dynamic>);
    } on DioException catch (e) { throw _h(e); }
  }

  @override
  Future<void> withdrawEarnings(double amount, String phoneNumber) async {
    try {
      await _dio.post('${ApiEndpoints.referral}/withdraw',
        data: {'amount': amount, 'phone_number': phoneNumber});
    } on DioException catch (e) { throw _h(e); }
  }

  Failure _h(DioException e) {
    if (e.type == DioExceptionType.connectionError) return const NetworkFailure();
    return ServerFailure(e.response?.data?['message'] as String? ?? 'Erreur parrainage');
  }
}
