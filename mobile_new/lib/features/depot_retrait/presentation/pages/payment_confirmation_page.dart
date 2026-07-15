import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/payment_provider.dart';

class PaymentConfirmationPage extends ConsumerStatefulWidget {
  final PaymentInitEntity paymentData;
  const PaymentConfirmationPage({super.key, required this.paymentData});

  @override
  ConsumerState<PaymentConfirmationPage> createState() => _PaymentConfirmationPageState();
}

class _PaymentConfirmationPageState extends ConsumerState<PaymentConfirmationPage> {
  late int _secondsLeft;
  Timer? _timer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.paymentData.expiresInSeconds;
    _startCountdown();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) { setState(() => _secondsLeft--); }
      else { _timer?.cancel(); }
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(paymentNotifierProvider.notifier)
          .checkStatus(widget.paymentData.transactionId);
    });
  }

  String get _timeFormatted {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft  % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exec = ref.watch(paymentNotifierProvider);

    ref.listen<PaymentExecState>(paymentNotifierProvider, (_, state) {
      if (state is PaymentSuccess) {
        _pollTimer?.cancel();
        _showSuccess();
      } else if (state is PaymentError) {
        _pollTimer?.cancel();
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            ref.read(paymentNotifierProvider.notifier).reset();
            context.go('/depot-retrait');
          },
        ),
        title: const Text('Finaliser le paiement'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 16),

            _TimerWidget(timeFormatted: _timeFormatted, secondsLeft: _secondsLeft,
              total: widget.paymentData.expiresInSeconds),

            const SizedBox(height: 28),

            if (widget.paymentData.ussdCode != null)
              _UssdInstructions(code: widget.paymentData.ussdCode!),

            if (widget.paymentData.walletAddress != null)
              _CryptoInstructions(
                address: widget.paymentData.walletAddress!,
                qrData:  widget.paymentData.qrCodeData,
              ),

            if (widget.paymentData.paymentUrl != null)
              _WebRedirectInstructions(url: widget.paymentData.paymentUrl!),

            const SizedBox(height: 24),

            _StatusPoll(exec: exec),

            const SizedBox(height: 24),

            _HelpSection(),
          ],
        ),
      ),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: context.cl.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
          SizedBox(height: 16),
          Text('Paiement réussi !', style: TextStyle(
            color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w700,
          ), textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('Ta transaction a été traitée avec succès.',
            style: TextStyle(color: context.cl.textS, fontSize: 13),
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              ref.read(paymentNotifierProvider.notifier).reset();
              ref.invalidate(walletProvider);
              ref.invalidate(transactionsProvider);
              context.go('/depot-retrait');
            },
            child: const Text('Retour'),
          ),
        ]),
      ),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  final String timeFormatted;
  final int secondsLeft, total;
  const _TimerWidget({required this.timeFormatted, required this.secondsLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / (total > 0 ? total : 1);
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(children: [
        Text('Temps restant', style: TextStyle(color: context.cl.textS, fontSize: 12)),
        const SizedBox(height: 8),
        Text(timeFormatted, style: TextStyle(
          color: secondsLeft < 60 ? AppColors.error : AppColors.primaryLight,
          fontSize: 36, fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: context.cl.surfaceD,
            valueColor: AlwaysStoppedAnimation<Color>(
              secondsLeft < 60 ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
      ]),
    );
  }
}

class _UssdInstructions extends StatelessWidget {
  final String code;
  const _UssdInstructions({required this.code});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.smartphone_rounded, color: AppColors.primaryLight, size: 20),
        SizedBox(width: 10),
        Text('Instructions Mobile Money', style: TextStyle(
          color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600,
        )),
      ]),
      const SizedBox(height: 16),
      _Step(num: '1', text: 'Ouvrez ton application Mobile Money'),
      _Step(num: '2', text: 'Sélectionne "Payer un marchand"'),
      _Step(num: '3', text: 'Composez le code USSD suivant :'),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Code copié !'), behavior: SnackBarBehavior.floating,
          ));
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(code, style: const TextStyle(
                color: AppColors.primaryLight, fontSize: 20,
                fontWeight: FontWeight.w800, letterSpacing: 2,
              )),
              const SizedBox(width: 12),
              const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      ),
      _Step(num: '4', text: 'Confirmez avec ton PIN Mobile Money'),
    ]),
  );
}

class _CryptoInstructions extends StatelessWidget {
  final String address;
  final String? qrData;
  const _CryptoInstructions({required this.address, this.qrData});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5),
    ),
    child: Column(children: [
      Row(children: [
        Icon(Icons.currency_bitcoin_rounded, color: Color(0xFFA78BFA), size: 20),
        SizedBox(width: 10),
        Text('Adresse de dépôt crypto', style: TextStyle(
          color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600,
        )),
      ]),
      SizedBox(height: 16),
      Container(
        width: double.infinity, padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.cl.surfaceD, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Text(address, style: TextStyle(
            color: context.cl.textS, fontSize: 11, fontFamily: 'monospace',
          ))),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
            onPressed: () {
              HapticFeedback.lightImpact();
              Clipboard.setData(ClipboardData(text: address));
            },
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
      ),
      SizedBox(height: 12),
      Text('Envoie exactement le montant indiqué à cette adresse.',
        style: TextStyle(color: context.cl.textS, fontSize: 12), textAlign: TextAlign.center),
      Text('3 confirmations réseau requises.',
        style: TextStyle(color: context.cl.textM, fontSize: 11), textAlign: TextAlign.center),
    ]),
  );
}

class _WebRedirectInstructions extends StatelessWidget {
  final String url;
  const _WebRedirectInstructions({required this.url});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5),
    ),
    child: Column(children: [
      Text('Finalisez le paiement sur la page sécurisée.',
        style: TextStyle(color: context.cl.textS, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        onPressed: () {/* launch url */},
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('Ouvrir la page de paiement'),
      ),
    ]),
  );
}

class _StatusPoll extends StatelessWidget {
  final PaymentExecState exec;
  const _StatusPoll({required this.exec});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5),
    ),
    child: Row(children: [
      if (exec is PaymentLoading) ...[
        SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
        SizedBox(width: 12),
        Text('Vérification du paiement en cours...', style: TextStyle(color: context.cl.textS, fontSize: 13)),
      ] else if (exec is PaymentError) ...[
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
        SizedBox(width: 10),
        Expanded(child: Text((exec as PaymentError).message,
          style: TextStyle(color: AppColors.error, fontSize: 13))),
      ] else ...[
        Icon(Icons.wifi_rounded, color: context.cl.textM, size: 20),
        SizedBox(width: 10),
        Text('En attente de confirmation...', style: TextStyle(color: context.cl.textM, fontSize: 13)),
      ],
    ]),
  );
}

class _HelpSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.info.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.info.withValues(alpha: 0.2), width: 0.5),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
      SizedBox(width: 10),
      Expanded(child: Text(
        'En cas de problème, contacte notre support avec ta référence de transaction. Le remboursement est traité sous 248h.',
        style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
      )),
    ]),
  );
}

class _Step extends StatelessWidget {
  final String num, text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Center(child: Text(num, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
      ),
      SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(color: context.cl.textS, fontSize: 13))),
    ]),
  );
}
