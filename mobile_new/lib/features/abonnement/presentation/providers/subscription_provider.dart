import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/network/dio_client.dart';

const _kSubFallback = {'plan': 'free', 'days_left': 0, 'premium_price': 5000, 'promo_code': 'PRONOWIN2025'};

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
    String?  xbetId,
    double?  amount,
    String?  senderPhone,
  }) async {
    state = ProofLoading();
    try {
      final r = await _dio.post(
        '/subscriptions/submit-proof',
        data: {
          'type':          type,
          'image_base64':  imageBase64,
          'xbet_id':      xbetId,
          'amount':        amount,
          'sender_phone':  senderPhone,
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
abstract class PromoState {}
class PromoIdle    extends PromoState {}
class PromoLoading extends PromoState {}
class PromoValid   extends PromoState {
  final PromoCode code;
  PromoValid(this.code);
}
class PromoInvalid extends PromoState {
  final String message;
  PromoInvalid(this.message);
}

class PromoCode {
  final String code, description;
  final int durationDays;
  const PromoCode({required this.code, required this.description, required this.durationDays});
}

class PromoNotifier extends StateNotifier<PromoState> {
  final Dio _dio;
  PromoNotifier(this._dio) : super(PromoIdle());

  Future<void> validate(String code) async {
    if (code.trim().isEmpty) return;
    state = PromoLoading();
    try {
      final r = await _dio.post('/subscriptions/validate-promo', data: {'code': code.trim()});
      final data = r.data as Map<String, dynamic>;
      if (data['valid'] == true) {
        state = PromoValid(PromoCode(
          code: code.trim(),
          description: data['description'] as String? ?? 'Code valide',
          durationDays: (data['duration_days'] as num?)?.toInt() ?? 30,
        ));
      } else {
        state = PromoInvalid(data['message'] as String? ?? 'Code invalide');
      }
    } catch (_) {
      state = PromoInvalid('Code invalide ou expiré');
    }
  }

  void reset() => state = PromoIdle();
}

final promoProvider = StateNotifierProvider<PromoNotifier, PromoState>(
  (ref) => PromoNotifier(ref.read(dioProvider)));

// ─── Abonnement via code promo ─────────────────────────────────────────────────
abstract class SubscribeState {}
class SubscribeIdle    extends SubscribeState {}
class SubscribeLoading extends SubscribeState {}
class SubscribeSuccess extends SubscribeState {}
class SubscribeError   extends SubscribeState {
  final String message;
  SubscribeError(this.message);
}

class SubscribeNotifier extends StateNotifier<SubscribeState> {
  final Dio _dio;
  SubscribeNotifier(this._dio) : super(SubscribeIdle());

  Future<void> subscribe({required String planId, required String paymentMethod, String? promoCode}) async {
    state = SubscribeLoading();
    try {
      await _dio.post('/subscriptions/subscribe', data: {
        'plan_id': planId, 'payment_method': paymentMethod,
        'promo_code': promoCode,
      });
      state = SubscribeSuccess();
    } catch (e) {
      state = SubscribeError('Erreur lors de la souscription');
    }
  }

  void reset() => state = SubscribeIdle();
}

final subscribeProvider = StateNotifierProvider<SubscribeNotifier, SubscribeState>(
  (ref) => SubscribeNotifier(ref.read(dioProvider)));
