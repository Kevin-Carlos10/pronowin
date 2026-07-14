import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../models/plan_model.dart';

abstract class SubscriptionDataSource {
  Future<List<PlanModel>>      getPlans();
  Future<SubscriptionModel?>   getCurrentSubscription();
  Future<SubscriptionModel>    subscribe({required String planId, required String paymentMethod, String? promoCode});
  Future<bool>                 validatePromoCode(String code);
  Future<void>                 cancelSubscription();
}

class SubscriptionDataSourceImpl implements SubscriptionDataSource {
  final Dio _dio;
  SubscriptionDataSourceImpl(this._dio);

  @override
  Future<List<PlanModel>> getPlans() async {
    try {
      final r = await _dio.get(ApiEndpoints.plans);
      return (r.data as List).map((e) => PlanModel.fromJson(e as Map<String,dynamic>)).toList();
    } on DioException catch (e) { throw _h(e); }
  }

  @override
  Future<SubscriptionModel?> getCurrentSubscription() async {
    try {
      final r = await _dio.get('/subscriptions/current');
      if (r.data == null) return null;
      return SubscriptionModel.fromJson(r.data as Map<String,dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _h(e);
    }
  }

  @override
  Future<SubscriptionModel> subscribe({required String planId, required String paymentMethod, String? promoCode}) async {
    try {
      final r = await _dio.post(ApiEndpoints.subscribe, data: {
        'plan_id': planId, 'payment_method': paymentMethod,
        'promo_code': promoCode,
      });
      return SubscriptionModel.fromJson(r.data as Map<String,dynamic>);
    } on DioException catch (e) { throw _h(e); }
  }

  @override
  Future<bool> validatePromoCode(String code) async {
    try {
      final r = await _dio.post(ApiEndpoints.promoCode, data: {'code': code});
      return r.data['valid'] as bool? ?? false;
    } on DioException catch (e) { throw _h(e); }
  }

  @override
  Future<void> cancelSubscription() async {
    try { await _dio.delete('/subscriptions/current'); }
    on DioException catch (e) { throw _h(e); }
  }

  Failure _h(DioException e) {
    if (e.type == DioExceptionType.connectionError) return const NetworkFailure();
    final msg = e.response?.data?['message'] as String?;
    return ServerFailure(msg ?? 'Erreur abonnement');
  }
}
