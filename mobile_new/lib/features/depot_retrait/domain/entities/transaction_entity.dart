import 'package:equatable/equatable.dart';

enum TransactionType   { deposit, withdrawal }
enum TransactionStatus { pending, completed, failed, cancelled }
enum PaymentMethod     { mobileMoney, card, crypto, bankTransfer }

class TransactionEntity extends Equatable {
  final String id;
  final TransactionType type;
  final double amount;
  final String currency;
  final PaymentMethod paymentMethod;
  final String provider;       // "Orange Money", "Moov", "MTN", "Stripe"...
  final TransactionStatus status;
  final String? providerRef;   // référence transaction côté provider
  final String? failureReason;
  final DateTime createdAt;

  const TransactionEntity({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.provider,
    required this.status,
    this.providerRef,
    this.failureReason,
    required this.createdAt,
  });

  bool get isDeposit    => type == TransactionType.deposit;
  bool get isCompleted  => status == TransactionStatus.completed;
  bool get isPending    => status == TransactionStatus.pending;
  bool get isFailed     => status == TransactionStatus.failed;

  String get formattedAmount {
    final sign = isDeposit ? '+' : '-';
    return '$sign${amount.toStringAsFixed(0)} FCFA';
  }

  @override
  List<Object?> get props => [id];
}

class PaymentInitEntity extends Equatable {
  final String transactionId;
  final String? paymentUrl;        // URL redirect CinetPay/Stripe
  final String? ussdCode;          // Code USSD Mobile Money
  final String? deepLink;          // Deep link vers app Mobile Money
  final String? walletAddress;     // Adresse crypto
  final String? qrCodeData;        // QR code crypto
  final int expiresInSeconds;

  const PaymentInitEntity({
    required this.transactionId,
    this.paymentUrl,
    this.ussdCode,
    this.deepLink,
    this.walletAddress,
    this.qrCodeData,
    required this.expiresInSeconds,
  });

  @override
  List<Object?> get props => [transactionId];
}

class WalletEntity extends Equatable {
  final double balance1xBet;
  final double balanceApp;
  final String currency;
  final DateTime lastUpdated;

  const WalletEntity({
    required this.balance1xBet,
    required this.balanceApp,
    required this.currency,
    required this.lastUpdated,
  });

  @override
  List<Object?> get props => [balance1xBet, balanceApp];
}
