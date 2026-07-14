import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../domain/entities/transaction_entity.dart';

// ─── Wallet ───────────────────────────────────────────────────────────────────
final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/payments/wallet');
    return r.data as Map<String, dynamic>;
  } catch (_) { return {}; }
});

// ─── Transactions ──────────────────────────────────────────────────────────────
final transactionsProvider = FutureProvider.autoDispose<List<TransactionEntity>>((ref) async {
  try {
    final r    = await ref.read(dioProvider).get('/payments/transactions');
    final list = (r.data['data'] as List? ?? []);
    return list.map((e) => _parseTransaction(e as Map<String, dynamic>)).toList();
  } catch (_) { return []; }
});

TransactionEntity _parseTransaction(Map<String, dynamic> j) {
  return TransactionEntity(
    id:            j['id'] as String,
    type:          j['type'] == 'deposit' ? TransactionType.deposit : TransactionType.withdrawal,
    amount:        (j['amount'] as num).toDouble(),
    currency:      j['currency'] as String? ?? 'XOF',
    paymentMethod: PaymentMethod.mobileMoney,
    provider:      j['payment_method'] as String? ?? '',
    status:        _parseStatus(j['status'] as String?),
    providerRef:   j['xbet_id'] as String?,
    failureReason: j['admin_note'] as String?,
    createdAt:     DateTime.parse(j['created_at'] as String),
  );
}

TransactionStatus _parseStatus(String? s) => switch (s) {
  'completed'  => TransactionStatus.completed,
  'rejected'   => TransactionStatus.failed,
  'processing' => TransactionStatus.pending,
  _            => TransactionStatus.pending,
};

// ─── État paiement ────────────────────────────────────────────────────────────
class PaymentSuccessData {
  final String transactionId;
  final String? mobcashNumber;
  final List<String> instructions;
  const PaymentSuccessData({required this.transactionId, this.mobcashNumber, required this.instructions});
}

abstract class PaymentExecState {}
class PaymentIdle    extends PaymentExecState {}
class PaymentLoading extends PaymentExecState {}
class PaymentSuccess extends PaymentExecState { final PaymentSuccessData data; PaymentSuccess(this.data); }
class PaymentError   extends PaymentExecState { final String message;          PaymentError(this.message); }

class PaymentNotifier extends StateNotifier<PaymentExecState> {
  final Dio _dio;
  PaymentNotifier(this._dio) : super(PaymentIdle());

  Future<void> submitManual({
    required TransactionType type,
    required double amount,
    required String method,
    required String xbetId,
    required String senderPhone,
  }) async {
    state = PaymentLoading();
    try {
      final r = await _dio.post('/payments/request', data: {
        'type':          type == TransactionType.deposit ? 'deposit' : 'withdrawal',
        'amount':        amount,
        'method':        method,
        'xbet_id':       xbetId,
        'sender_phone':  senderPhone,
      });
      final d = r.data as Map<String, dynamic>;
      state = PaymentSuccess(PaymentSuccessData(
        transactionId: d['transaction_id'] as String,
        mobcashNumber: d['mobcash_number'] as String?,
        instructions:  (d['instructions'] as List? ?? []).cast<String>(),
      ));
    } on DioException catch (e) {
      state = PaymentError(e.response?.data?['message'] as String? ?? 'Erreur lors de la demande.');
    }
  }

  Future<void> checkStatus(String transactionId) async {
    if (state is PaymentSuccess) return; // Déjà confirmé
    try {
      final r = await _dio.get('/payments/transactions/$transactionId/status');
      final status = r.data['status'] as String?;
      if (status == 'completed') {
        state = PaymentSuccess(PaymentSuccessData(
          transactionId: transactionId,
          instructions: [],
        ));
      } else if (status == 'rejected' || status == 'failed') {
        state = PaymentError(r.data['message'] as String? ?? 'Paiement refusé.');
      }
    } catch (_) { /* Silence — on réessaie au prochain tick */ }
  }

  void reset() => state = PaymentIdle();
}

final paymentNotifierProvider = StateNotifierProvider<PaymentNotifier, PaymentExecState>(
  (ref) => PaymentNotifier(ref.read(dioProvider)));

/// Filtre type transaction dans l'historique : null=tous
final txTypeFilterProvider = StateProvider<TransactionType?>((ref) => null);

/// Filtre statut transaction : null=tous
final txStatusFilterProvider = StateProvider<TransactionStatus?>((ref) => null);

/// Historique filtré
final filteredTransactionsProvider = Provider<List<TransactionEntity>>((ref) {
  final list       = ref.watch(transactionsProvider).valueOrNull ?? [];
  final typeFilter = ref.watch(txTypeFilterProvider);
  final statFilter = ref.watch(txStatusFilterProvider);
  return list.where((t) {
    if (typeFilter != null && t.type != typeFilter)   return false;
    if (statFilter != null && t.status != statFilter) return false;
    return true;
  }).toList();
});
