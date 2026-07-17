import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bankroll_provider.dart';

Future<bool> showMiserDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String  pronosticId,
  required String  homeTeam,
  required String  awayTeam,
  required String  predictionLabel,
  required int     confidenceScore,
  required double  oddsRecommended,
}) async {
  final result = await showModalBottomSheet<bool>(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    barrierColor:       Colors.black54,
    builder: (_) => _MiserSheet(
      pronosticId:     pronosticId,
      homeTeam:        homeTeam,
      awayTeam:        awayTeam,
      predictionLabel: predictionLabel,
      confidenceScore: confidenceScore,
      oddsRecommended: oddsRecommended,
    ),
  );
  return result ?? false;
}

// ─── Sheet ────────────────────────────────────────────────────────────────────
class _MiserSheet extends ConsumerStatefulWidget {
  final String  pronosticId;
  final String  homeTeam;
  final String  awayTeam;
  final String  predictionLabel;
  final int     confidenceScore;
  final double  oddsRecommended;

  const _MiserSheet({
    required this.pronosticId,
    required this.homeTeam,
    required this.awayTeam,
    required this.predictionLabel,
    required this.confidenceScore,
    required this.oddsRecommended,
  });

  @override
  ConsumerState<_MiserSheet> createState() => _MiserSheetState();
}

class _MiserSheetState extends ConsumerState<_MiserSheet> {
  bool    _loading    = false;
  String? _error;
  bool    _alreadyBet = false;
  bool    _confirmed  = false;
  double? _confirmedStake;
  String? _confirmedCurrency;

  // confidenceScore = 1-5 (étoiles choisies par l'admin à la publication)
  String get _ruleLabel {
    if (widget.confidenceScore >= 5) return '5% du solde  ·  Confiance maximale';
    if (widget.confidenceScore >= 3) return '3% du solde  ·  Confiance moyenne';
    return '1,5% du solde  ·  Confiance faible';
  }

  Color get _confColor {
    if (widget.confidenceScore >= 5) return AppColors.success;
    if (widget.confidenceScore >= 3) return AppColors.warning;
    return AppColors.error;
  }

  String get _confLabel {
    if (widget.confidenceScore >= 5) return '${widget.confidenceScore}/5';
    if (widget.confidenceScore >= 3) return '${widget.confidenceScore}/5';
    return '${widget.confidenceScore}/5';
  }

  Future<void> _launch1xBet() async {
    const url = 'https://1xbet.com';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _submit(double stake, String currency) async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(dioProvider).post('/bankroll/bet', data: {
        'pronostic_id':  widget.pronosticId,
        'staked_amount': stake,
      });
      ref.invalidate(bankrollProvider);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() {
        _confirmed        = true;
        _confirmedStake   = stake;
        _confirmedCurrency = currency;
        _loading          = false;
      });
    } catch (e) {
      String msg;
      if (e is DioException) {
        final code    = e.response?.data?['code']    as String?;
        final srvMsg  = e.response?.data?['message'] as String?;
        if (code == 'BET_ALREADY_PLACED' || srvMsg?.contains('déjà misé') == true) {
          msg = 'Tu as déjà placé un pari sur ce match.';
          _alreadyBet = true;
        } else if (srvMsg?.contains('Solde insuffisant') == true) {
          msg = 'Solde insuffisant dans ton bankroll.';
        } else {
          msg = srvMsg ?? 'Erreur lors de la mise.';
        }
      } else {
        msg = 'Erreur lors de la mise.';
      }
      setState(() { _error = msg; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestAsync = ref.watch(suggestedStakeProvider(widget.confidenceScore));

    // ── Vue post-confirmation ────────────────────────────────────────────────
    if (_confirmed && _confirmedStake != null) {
      return Container(
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: context.cl.border, borderRadius: BorderRadius.circular(2))),

          // Succès
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 34)),
          const SizedBox(height: 14),
          Text('Mise enregistrée !', style: TextStyle(
            color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '${_formatAmount(_confirmedStake!)} ${_confirmedCurrency ?? ''} · ${widget.homeTeam} – ${widget.awayTeam}',
            style: TextStyle(color: context.cl.textM, fontSize: 12),
            textAlign: TextAlign.center),

          const SizedBox(height: 20),

          // Alerte discipline
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3), width: 0.8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shield_rounded, color: AppColors.warning, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Rappel de discipline', style: TextStyle(
                  color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Mise exactement ${_formatAmount(_confirmedStake!)} ${_confirmedCurrency ?? ''} sur le bookmaker. Ne dépasse jamais ce montant, même si tu te sens confiant.',
                  style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.45)),
              ])),
            ]),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 16),

          // Bouton 1xBet
          GestureDetector(
            onTap: _launch1xBet,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A73E8), Color(0xFF1557B0)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF1A73E8).withValues(alpha: 0.35),
                  blurRadius: 12, offset: const Offset(0, 5))]),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Aller miser sur', style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                SizedBox(width: 6),
                Text('1xBet', style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ]),
            ),
          ).animate(delay: 80.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 10),

          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Fermer', style: TextStyle(
              color: context.cl.textM, fontSize: 13))),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: suggestAsync.when(
        loading: () => const _LoadingSkeleton(),
        error: (e, _) => _ErrorView(
          message: e.toString().contains('Configure')
              ? 'Configure ton budget bankroll d\'abord.'
              : 'Impossible de calculer la mise.'),
        data: (s) {
          final stake    = (s['suggested_amount'] as num).toDouble();
          final balance  = (s['current_balance']  as num).toDouble();
          final currency = s['currency'] as String;
          final gain     = stake * widget.oddsRecommended;

          return Column(mainAxisSize: MainAxisSize.min, children: [

            // Handle
            Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: context.cl.border, borderRadius: BorderRadius.circular(2))),

            // Titre
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
                child: const Icon(Icons.savings_rounded,
                  color: AppColors.success, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Valider ma mise', style: TextStyle(
                  color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${widget.homeTeam} – ${widget.awayTeam}',
                  style: TextStyle(color: context.cl.textM, fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),

            const SizedBox(height: 20),

            // Info pronostic
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: context.cl.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cl.border, width: 0.5)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pronostic', style: TextStyle(color: context.cl.textM, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(widget.predictionLabel, style: TextStyle(
                    color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Cote', style: TextStyle(color: context.cl.textM, fontSize: 10)),
                  Text('x${widget.oddsRecommended.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.primary,
                      fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Confiance', style: TextStyle(color: context.cl.textM, fontSize: 10)),
                  Row(children: [
                    Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: _confColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(_confLabel, style: TextStyle(
                      color: _confColor, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ]),
            ),

            const SizedBox(height: 16),

            // ── Mise fixée par l'algorithme ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.success.withValues(alpha: 0.10),
                  AppColors.success.withValues(alpha: 0.04),
                ]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3), width: 1)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Mise calculée', style: TextStyle(
                      color: context.cl.textS, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${_formatAmount(stake)} $currency',
                      style: const TextStyle(
                        color: AppColors.success, fontSize: 28,
                        fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _confColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _confColor.withValues(alpha: 0.3), width: 0.7)),
                    child: Text(_ruleLabel, style: TextStyle(
                      color: _confColor, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 10),
                Divider(color: AppColors.success.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.info_outline_rounded,
                    color: AppColors.success, size: 13),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Montant fixé par la discipline bankroll — non modifiable.',
                    style: TextStyle(color: context.cl.textS, fontSize: 11))),
                ]),
              ]),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0),

            const SizedBox(height: 12),

            // Gain potentiel + solde restant
            Row(children: [
              Expanded(child: _InfoChip(
                label: 'Gain potentiel',
                value: '+${_formatAmount(gain)} $currency',
                color: AppColors.primary)),
              const SizedBox(width: 10),
              Expanded(child: _InfoChip(
                label: 'Solde après',
                value: '${_formatAmount(balance - stake)} $currency',
                color: context.cl.textS)),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (_alreadyBet ? AppColors.warning : AppColors.error).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_alreadyBet ? AppColors.warning : AppColors.error).withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    _alreadyBet ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                    color: _alreadyBet ? AppColors.warning : AppColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(
                    color: _alreadyBet ? AppColors.warning : AppColors.error,
                    fontSize: 12,
                    height: 1.4,
                  ))),
                ]),
              ),
            ],

            const SizedBox(height: 20),

            // Bouton confirmer
            GestureDetector(
              onTap: (_loading || _alreadyBet) ? null : () => _submit(stake, currency),
              child: AnimatedContainer(
                duration: 200.ms,
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: (_loading || _alreadyBet)
                      ? [AppColors.success.withValues(alpha: 0.5),
                         const Color(0xFF059669).withValues(alpha: 0.5)]
                      : [AppColors.success, const Color(0xFF059669)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _loading ? [] : [BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.4),
                    blurRadius: 14, offset: const Offset(0, 6))]),
                child: Center(child: _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Confirmer la mise', style: TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                    ])),
              ),
            ),

            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(
                color: context.cl.textM, fontSize: 13)),
            ),
          ]);
        },
      ),
    );
  }
}

// ─── Chip info ────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _InfoChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: context.cl.textM, fontSize: 10)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(
        color: color, fontSize: 13, fontWeight: FontWeight.w700),
        maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─── Skeleton loading ─────────────────────────────────────────────────────────
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 60),
      const CircularProgressIndicator(color: AppColors.success, strokeWidth: 2),
      const SizedBox(height: 60),
    ],
  );
}

// ─── Vue erreur ───────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.account_balance_wallet_outlined,
        color: AppColors.warning, size: 40),
      const SizedBox(height: 12),
      Text(message, style: TextStyle(color: context.cl.textS, fontSize: 14),
        textAlign: TextAlign.center),
      const SizedBox(height: 20),
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Fermer')),
    ]),
  );
}

// ─── Formatter ────────────────────────────────────────────────────────────────
String _formatAmount(double amount) {
  final s   = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return amount < 0 ? '-${buf.toString()}' : buf.toString();
}
