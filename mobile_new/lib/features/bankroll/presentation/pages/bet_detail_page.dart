import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bankroll_provider.dart';

class BetDetailPage extends StatelessWidget {
  final BankrollBet bet;
  const BetDetailPage({super.key, required this.bet});

  @override
  Widget build(BuildContext context) {
    final isPending = bet.result == null;
    final isWin     = bet.result == 'WIN';
    final cl        = context.cl;

    final statusColor = isPending ? AppColors.warning
                      : isWin    ? AppColors.success
                      :             AppColors.error;
    final statusLabel = isPending ? 'En attente'
                      : isWin    ? 'Gagné'
                      :             'Perdu';
    final statusIcon  = isPending ? Icons.hourglass_empty_rounded
                      : isWin    ? Icons.emoji_events_rounded
                      :             Icons.close_rounded;

    return Scaffold(
      backgroundColor: cl.bg,
      appBar: AppBar(
        backgroundColor: cl.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Détail du pari',
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ── Badge résultat ────────────────────────────────────────────────
          Center(
            child: Column(children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Icon(statusIcon, color: statusColor, size: 36),
              ).animate().scale(begin: const Offset(0.7, 0.7), duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w700)),
              ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Carte match ───────────────────────────────────────────────────
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RowLabel(icon: Icons.sports_soccer_rounded, label: 'Match'),
              const SizedBox(height: 10),
              Text('${bet.homeTeam}  –  ${bet.awayTeam}',
                style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.emoji_flags_rounded, size: 13, color: cl.textM),
                const SizedBox(width: 5),
                Text(bet.league, style: TextStyle(color: cl.textM, fontSize: 12)),
              ]),
              if (bet.settledAt != null || bet.createdAt != DateTime(0)) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 13, color: cl.textM),
                  const SizedBox(width: 5),
                  Text(_formatDate(bet.settledAt ?? bet.createdAt),
                    style: TextStyle(color: cl.textM, fontSize: 12)),
                ]),
              ],
            ]),
          ).animate().fadeIn(duration: 350.ms, delay: 100.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 12),

          // ── Carte pronostic ───────────────────────────────────────────────
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RowLabel(icon: Icons.auto_awesome_rounded, label: 'Pronostic choisi'),
              const SizedBox(height: 10),
              Text(bet.predictionLabel,
                style: TextStyle(color: cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(children: [
                _Chip(
                  label: 'Cote  x${bet.oddsUsed.toStringAsFixed(2)}',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'Confiance  ${bet.confidenceScore}/5',
                  color: AppColors.info,
                ),
              ]),
            ]),
          ).animate().fadeIn(duration: 350.ms, delay: 180.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 12),

          // ── Carte financière ──────────────────────────────────────────────
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RowLabel(icon: Icons.account_balance_wallet_rounded, label: 'Financier'),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _FinanceStat(
                  label: 'Mise',
                  value: '${_formatAmount(bet.stakedAmount)} XOF',
                  valueColor: cl.textP,
                )),
                Container(width: 1, height: 40, color: cl.border),
                Expanded(child: _FinanceStat(
                  label: 'Gain potentiel',
                  value: '+${_formatAmount(bet.potentialGain)} XOF',
                  valueColor: AppColors.primary,
                )),
              ]),
              if (bet.profit != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (bet.profit! >= 0 ? AppColors.success : AppColors.error)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (bet.profit! >= 0 ? AppColors.success : AppColors.error)
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      bet.profit! >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: bet.profit! >= 0 ? AppColors.success : AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Résultat net',
                        style: TextStyle(color: cl.textM, fontSize: 11)),
                      Text(
                        '${bet.profit! >= 0 ? '+' : ''}${_formatAmount(bet.profit!)} XOF',
                        style: TextStyle(
                          color: bet.profit! >= 0 ? AppColors.success : AppColors.error,
                          fontSize: 16, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ]),
                  ]),
                ),
              ],
            ]),
          ).animate().fadeIn(duration: 350.ms, delay: 260.ms).slideY(begin: 0.05, end: 0),

          // ── Date du pari ──────────────────────────────────────────────────
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Pari placé le ${_formatDateFull(bet.createdAt)}',
              style: TextStyle(color: cl.textM, fontSize: 11),
            ),
          ),
        ]),
      ),
    );
  }

  static String _formatAmount(double v) {
    final k = v >= 1000;
    if (!k) return v.toStringAsFixed(0);
    final s = (v / 1000);
    return '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1)} k';
  }

  static String _formatDate(DateTime d) {
    const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun',
                    'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _formatDateFull(DateTime d) {
    const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return '${d.day} ${months[d.month - 1]} ${d.year} à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Sous-widgets ──────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5),
    ),
    child: child,
  );
}

class _RowLabel extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _RowLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: AppColors.primary),
    const SizedBox(width: 6),
    Text(label.toUpperCase(),
      style: TextStyle(color: context.cl.textS, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  ]);
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _FinanceStat extends StatelessWidget {
  final String label, value;
  final Color  valueColor;
  const _FinanceStat({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label,
      style: TextStyle(color: context.cl.textM, fontSize: 11)),
    const SizedBox(height: 4),
    Text(value,
      style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w800),
      textAlign: TextAlign.center),
  ]);
}
