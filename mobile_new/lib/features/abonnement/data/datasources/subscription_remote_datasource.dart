import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../models/plan_model.dart';

abstract class SubscriptionRemoteDataSource {
  Future<List<PlanModel>>      getPlans();
  Future<SubscriptionModel>    getCurrentSubscription();
  Future<SubscriptionModel>    subscribe({required String planId, required String paymentMethod, String? promoCode});
  Future<PromoCodeModel>       validatePromoCode(String code);
  Future<void>                 cancelSubscription();
}

class SubscriptionRemoteDataSourceImpl implements SubscriptionRemoteDataSource {
  final Dio _dio;
  SubscriptionRemoteDataSourceImpl(this._dio);

  @override
  Future<List<PlanModel>> getPlans() async {
    try {
      final r = await _dio.get(ApiEndpoints.plans);
      return (r.data as List).map((e) => PlanModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<SubscriptionModel> getCurrentSubscription() async {
    try {
      final r = await _dio.get('/subscriptions/current');
      return SubscriptionModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<SubscriptionModel> subscribe({required String planId, required String paymentMethod, String? promoCode}) async {
    try {
      final r = await _dio.post(ApiEndpoints.subscribe, data: {
        'plan_id': planId, 'payment_method': paymentMethod,
        'promo_code': promoCode,
      });
      return SubscriptionModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<PromoCodeModel> validatePromoCode(String code) async {
    try {
      final r = await _dio.post(ApiEndpoints.promoCode, data: {'code': code});
      return PromoCodeModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<void> cancelSubscription() async {
    try { await _dio.delete('/subscriptions/cancel'); }
    on DioException catch (e) { throw _handle(e); }
  }

  Failure _handle(DioException e, [String? ctx]) =>
      handleDioException(e, context: ctx);
}
