import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/network/dio_client.dart';

const _kSubFallback = {
  'plan': 'free', 'days_left': 0, 'promo_code': 'PRONOWIN2025',
  'betting_platforms': ['1xbet', 'melbet', 'betwinner'],
  'premium_price_monthly_usd': 10, 'premium_price_annual_usd': 90,
  'premium_price_monthly_fcfa': 6000, 'premium_price_annual_fcfa': 54000,
  'premium_price_monthly_code_usd': 7, 'premium_price_annual_code_usd': 63,
  'premium_price_monthly_code_fcfa': 4200, 'premium_price_annual_code_fcfa': 37800,
  'premium_price_monthly_store_usd': 15, 'premium_price_annual_store_usd': 135,
};

// ─── Abonnement actuel ────────────────────────────────────────────────────────
final currentSubscriptionProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  const cacheKey = 'subscription_current';
  try {
    final r    = await ref.read(dioProvider).get('/subscriptions/current');
    final data = r.data as Map<String, dynamic>;
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    return await CacheService.loadStale<Map<String, dynamic>>(
      cacheKey, (d) => d as Map<String, dynamic>) ?? _kSubFallback;
  }
});

// ─── Statut preuve ────────────────────────────────────────────────────────────
final proofStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/subscriptions/proof-status');
    if (r.data?['status'] == 'none') return null;
    return r.data as Map<String, dynamic>;
  } catch (_) { return null; }
});

// ─── État soumission de preuve ────────────────────────────────────────────────
abstract class SubmitProofState {}
class ProofIdle      extends SubmitProofState {}
class ProofLoading   extends SubmitProofState {}
class ProofSubmitted extends SubmitProofState {
  final String estimatedTime;
  ProofSubmitted(this.estimatedTime);
}
class ProofError extends SubmitProofState {
  final String message;
  ProofError(this.message);
}

class SubmitProofNotifier extends StateNotifier<SubmitProofState> {
  final Dio _dio;
  SubmitProofNotifier(this._dio) : super(ProofIdle());

  Future<void> submit({
    required String type,
    required String imageBase64,
    String?  paymentImageBase64,
    String?  xbetId,
    String?  platform,
    double?  amount,
    String?  senderPhone,
    String?  planId,
  }) async {
    state = ProofLoading();
    try {
      final r = await _dio.post(
        '/subscriptions/submit-proof',
        data: {
          'type':                 type,
          'image_base64':         imageBase64,
          'payment_image_base64': paymentImageBase64,
          'xbet_id':              xbetId,
          'platform':             platform,
          'amount':               amount,
          'sender_phone':         senderPhone,
          'plan_id':              planId,
        },
        options: Options(
          sendTimeout:    const Duration(seconds: 60), // Image peut être lourde
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final estimated = r.data['estimated_review'] as String? ?? '30 minutes';
      state = ProofSubmitted(estimated);
    } on DioException catch (e) {
      state = ProofError(e.response?.data?['message'] as String? ?? 'Erreur lors de l\'envoi.');
    }
  }

  void reset() => state = ProofIdle();
}

final submitProofProvider = StateNotifierProvider<SubmitProofNotifier, SubmitProofState>(
  (ref) => SubmitProofNotifier(ref.read(dioProvider)));

// ─── Validation code promo ─────────────────────────────────────────────────────
