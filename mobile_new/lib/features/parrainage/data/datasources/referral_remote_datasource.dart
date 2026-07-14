import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../models/referral_model.dart';

abstract class ReferralRemoteDataSource {
  Future<ReferralStatsModel>    getStats();
  Future<List<ReferralModel>>   getReferrals({int page});
  Future<void>                  withdrawEarnings(double amount, String phone);
}

class ReferralRemoteDataSourceImpl implements ReferralRemoteDataSource {
  final Dio _dio;
  ReferralRemoteDataSourceImpl(this._dio);

  @override
  Future<ReferralStatsModel> getStats() async {
    try {
      final r = await _dio.get(ApiEndpoints.referral);
      return ReferralStatsModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<List<ReferralModel>> getReferrals({int page = 1}) async {
    try {
      final r = await _dio.get('${ApiEndpoints.referral}/list', queryParameters: {'page': page});
      return (r.data['data'] as List).map((e) => ReferralModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<void> withdrawEarnings(double amount, String phone) async {
    try {
      await _dio.post('${ApiEndpoints.referral}/withdraw', data: {'amount': amount, 'phone_number': phone});
    } on DioException catch (e) { throw _handle(e); }
  }

  Failure _handle(DioException e, [String? ctx]) =>
      handleDioException(e, context: ctx);
}
