import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bankroll_provider.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/montant.dart';
import '../../../pronostics/domain/entities/match_entity.dart';

class BetDetailPage extends StatelessWidget {
  final BankrollBet bet;
  const BetDetailPage({super.key, required this.bet});

  @override
  Widget build(BuildContext context) {
    final isPending = bet.result == null;
    final isWin     = bet.result == 'WIN';
    final isPush    = bet.result == 'PUSH';
    final cl        = context.cl;

    final statusColor = isPending ? AppColors.warning
                      : isWin    ? AppColors.success
                      : isPush   ? AppColors.info
                      :             AppColors.error;
    final statusLabel = isPending ? 'En attente'
                      : isWin    ? 'Gagné'
                      : isPush   ? 'Remboursé'
                      :             'Perdu';
    final statusIcon  = isPending ? Icons.hourglass_empty_rounded
                      : isWin    ? Icons.emoji_events_rounded
                      : isPush   ? Icons.replay_rounded
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
              Text(bet.displayPredictionLabel,
                style: TextStyle(color: cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(children: [
                // « Cote x1.35 » : le préfixe n'existait qu'ici, partout
                // ailleurs la cote se lit nue.
                _Chip(
                  label: 'Cote  ${bet.oddsUsed.toStringAsFixed(2)}',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                // « 3/5 » se lit 60 %, alors que la conversion de l'app donne
                // 80 % pour ce même score — la page détail du match affichait
                // donc vingt points de plus pour la même donnée. Une seule
                // échelle, celle qui fait déjà autorité ailleurs.
                _Chip(
                  label: 'Confiance  '
                         '${MatchEntity.percentForConfidence(bet.confidenceScore)} %',
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

              // Le calcul est posé au lieu d'être résumé.
              //
              // « Gain potentiel  +2 025 » était l'affirmation la plus coûteuse
              // de l'écran : `potentialGain` vaut mise × cote, c'est-à-dire le
              // **retour total**, mise comprise. Le « + » le faisait lire comme
              // un bénéfice. Le parieur croyait gagner 2 025 ; il gagnera 525 —
              // exactement sa mise d'écart. Montrer les trois lignes supprime
              // l'ambiguïté sans rien exiger du lecteur.
              _LigneCalcul(
                libelle: 'Mise',
                montant: '${montantExact(bet.stakedAmount)} ${nomDevise(bet.currency)}',
              ),
              const SizedBox(height: 8),
              _LigneCalcul(
                libelle: 'Cote',
                montant: '× ${bet.oddsUsed.toStringAsFixed(2)}',
                attenue: true,
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: cl.border),
              const SizedBox(height: 12),

              // Retour total — l'information que le parieur verra chez le
              // bookmaker, en gros parce que c'est celle qu'il compare.
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isPending ? 'Retour si gagné' : 'Retour',
                      style: TextStyle(color: cl.textM, fontSize: 11.5)),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${montantExact(bet.potentialGain)} ${nomDevise(bet.currency)}',
                        style: TextStyle(color: cl.textP, fontSize: 26,
                            fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                // Le bénéfice réel, distinct du retour : c'est ce que le
                // parieur gagne vraiment.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.35), width: 0.8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('dont bénéfice',
                      style: TextStyle(color: cl.textM, fontSize: 9.5,
                          fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(montantSigne(bet.potentialGain - bet.stakedAmount),
                      style: const TextStyle(color: AppColors.success,
                          fontSize: 16, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ]),
              if (bet.profit != null) ...[
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final profitColor = isPush ? AppColors.info
                    : bet.profit! >= 0 ? AppColors.success : AppColors.error;
                  final profitIcon = isPush ? Icons.replay_rounded
                    : bet.profit! >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
                  final profitText = isPush
                    ? 'Mise remboursée'
                    : '${bet.profit! >= 0 ? '+' : ''}${montantExact(bet.profit!)} ${nomDevise(bet.currency)}';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: profitColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: profitColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Icon(profitIcon, color: profitColor, size: 20),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Résultat net',
                          style: TextStyle(color: cl.textM, fontSize: 11)),
                        Text(profitText,
                          style: TextStyle(
                            color: profitColor,
                            fontSize: 16, fontWeight: FontWeight.w800,
                          ),
                        ),
                      ]),
                    ]),
                  );
                }),
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

  /// « 19 aoû 2026 » et « 19 août 2026 » cohabitaient sur le même écran.
  /// « aoû » n'est l'abréviation d'usage de personne, et la place ne manque
  /// pas : les deux dates s'écrivent désormais pareil.
  static String _formatDate(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

  static const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  static String _formatDateFull(DateTime d) =>
      '${_formatDate(d)} à ${d.hour.toString().padLeft(2, '0')}'
      'h${d.minute.toString().padLeft(2, '0')}';
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

/// Une ligne du calcul : libellé à gauche, valeur à droite.
///
/// La cote est [attenue] — c'est un opérateur, pas un montant : la mettre au
/// même niveau visuel que la mise laisserait croire à une seconde somme.
class _LigneCalcul extends StatelessWidget {
  final String libelle, montant;
  final bool   attenue;
  const _LigneCalcul({
    required this.libelle, required this.montant, this.attenue = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(libelle,
        style: TextStyle(color: context.cl.textM, fontSize: 12.5)),
      Text(montant,
        style: TextStyle(
          color: attenue ? context.cl.textM : context.cl.textP,
          fontSize: attenue ? 13 : 14.5,
          fontWeight: attenue ? FontWeight.w600 : FontWeight.w700)),
    ],
  );
}

