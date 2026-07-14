import '../../domain/entities/transaction_entity.dart';

class TransactionModel extends TransactionEntity {
  const TransactionModel({
    required super.id,
    required super.type,
    required super.amount,
    required super.currency,
    required super.paymentMethod,
    required super.provider,
    required super.status,
    super.providerRef,
    super.failureReason,
    required super.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> j) => TransactionModel(
    id:            j['id'] as String,
    type:          j['type'] == 'deposit' ? TransactionType.deposit : TransactionType.withdrawal,
    amount:        (j['amount'] as num).toDouble(),
    currency:      j['currency'] as String? ?? 'XOF',
    paymentMethod: _parseMethod(j['payment_method'] as String?),
    provider:      j['provider'] as String? ?? '',
    status:        _parseStatus(j['status'] as String?),
    providerRef:   j['provider_transaction_id'] as String?,
    failureReason: j['failure_reason'] as String?,
    createdAt:     DateTime.parse(j['created_at'] as String),
  );

  static PaymentMethod _parseMethod(String? s) => switch (s) {
    'card'          => PaymentMethod.card,
    'crypto'        => PaymentMethod.crypto,
    'bank_transfer' => PaymentMethod.bankTransfer,
    _               => PaymentMethod.mobileMoney,
  };

  static TransactionStatus _parseStatus(String? s) => switch (s) {
    'completed'  => TransactionStatus.completed,
    'failed'     => TransactionStatus.failed,
    'cancelled'  => TransactionStatus.cancelled,
    _            => TransactionStatus.pending,
  };
}

class PaymentInitModel extends PaymentInitEntity {
  const PaymentInitModel({
    required super.transactionId,
    super.paymentUrl,
    super.ussdCode,
    super.deepLink,
    super.walletAddress,
    super.qrCodeData,
    required super.expiresInSeconds,
  });

  factory PaymentInitModel.fromJson(Map<String, dynamic> j) => PaymentInitModel(
    transactionId:   j['transaction_id'] as String,
    paymentUrl:      j['payment_url'] as String?,
    ussdCode:        j['ussd_code'] as String?,
    deepLink:        j['deep_link'] as String?,
    walletAddress:   j['wallet_address'] as String?,
    qrCodeData:      j['qr_code_data'] as String?,
    expiresInSeconds: j['expires_in_seconds'] as int? ?? 600,
  );
}

class WalletModel extends WalletEntity {
  const WalletModel({
    required super.balance1xBet,
    required super.balanceApp,
    required super.currency,
    required super.lastUpdated,
  });

  factory WalletModel.fromJson(Map<String, dynamic> j) => WalletModel(
    balance1xBet: (j['balance_1xbet'] as num?)?.toDouble() ?? 0.0,
    balanceApp:   (j['balance_app']  as num?)?.toDouble() ?? 0.0,
    currency:     j['currency'] as String? ?? 'XOF',
    lastUpdated:  DateTime.parse(j['last_updated'] as String? ?? DateTime.now().toIso8601String()),
  );
}
