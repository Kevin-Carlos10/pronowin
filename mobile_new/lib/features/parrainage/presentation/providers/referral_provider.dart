import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';

// ─── Stats parrainage ─────────────────────────────────────────────────────────
final referralStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/referral');
    return r.data as Map<String, dynamic>;
  } catch (e) {
    return {
      'referral_code': '------',
      'total_earnings': 0,
      'can_withdraw': false,
      'min_withdrawal': 2000,
      'commission_l1': 500,
      'commission_l2': 200,
      'stats': {'total_l1': 0, 'premium_l1': 0, 'total_l2': 0, 'premium_l2': 0, 'total_referrals': 0},
      'l1_referrals': [],
      'l2_referrals': [],
    };
  }
});

// ─── Historique gains ─────────────────────────────────────────────────────────
final referralHistoryProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/referral/history');
    return r.data as List<dynamic>;
  } catch (_) { return []; }
});

// ─── État application code parrain ───────────────────────────────────────────
abstract class ApplyCodeState {}
class ApplyCodeIdle    extends ApplyCodeState {}
class ApplyCodeLoading extends ApplyCodeState {}
class ApplyCodeSuccess extends ApplyCodeState { final String referrerPseudo; ApplyCodeSuccess(this.referrerPseudo); }
class ApplyCodeError   extends ApplyCodeState { final String message;       ApplyCodeError(this.message); }

class ApplyCodeNotifier extends StateNotifier<ApplyCodeState> {
  final Dio _dio;
  ApplyCodeNotifier(this._dio) : super(ApplyCodeIdle());

  Future<void> apply(String code) async {
    state = ApplyCodeLoading();
    try {
      final r = await _dio.post('/referral/apply-code', data: {'referral_code': code});
      state = ApplyCodeSuccess(r.data['referrer_pseudo'] as String? ?? '');
    } on DioException catch (e) {
      state = ApplyCodeError(e.response?.data?['message'] as String? ?? 'Erreur.');
    }
  }

  void reset() => state = ApplyCodeIdle();
}

final applyCodeProvider = StateNotifierProvider<ApplyCodeNotifier, ApplyCodeState>(
  (ref) => ApplyCodeNotifier(ref.read(dioProvider)));

// ─── État retrait ─────────────────────────────────────────────────────────────
abstract class WithdrawState {}
class WithdrawIdle    extends WithdrawState {}
class WithdrawLoading extends WithdrawState {}
class WithdrawSuccess extends WithdrawState { final String message; WithdrawSuccess(this.message); }
class WithdrawError   extends WithdrawState { final String message; WithdrawError(this.message); }

class WithdrawNotifier extends StateNotifier<WithdrawState> {
  final Dio _dio;
  WithdrawNotifier(this._dio) : super(WithdrawIdle());

  Future<void> withdraw({
    required double amount,
    required String method,
    required String phone,
    required bool   useAsCredit,
  }) async {
    state = WithdrawLoading();
    try {
      final r = await _dio.post('/referral/withdraw', data: {
        'amount':        amount,
        'method':        method,
        'phone':         phone,
        'use_as_credit': useAsCredit,
      });
      state = WithdrawSuccess(r.data['message'] as String? ?? 'Succès.');
    } on DioException catch (e) {
      state = WithdrawError(e.response?.data?['message'] as String? ?? 'Erreur.');
    }
  }

  void reset() => state = WithdrawIdle();
}

final withdrawProvider = StateNotifierProvider<WithdrawNotifier, WithdrawState>(
  (ref) => WithdrawNotifier(ref.read(dioProvider)));
