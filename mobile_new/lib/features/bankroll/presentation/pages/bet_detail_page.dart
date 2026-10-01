import 'package:intl/intl.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/widgets/confidence_indicator.dart';
import '../providers/bankroll_provider.dart';
import '../widgets/confirmation_mise.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/montant.dart';
import '../../../pronostics/domain/entities/match_entity.dart';

/// La fiche d'un pari.
///
/// ── Ce qu'elle était ─────────────────────────────────────────────────────
///
/// Un grand sablier et une pastille « En attente » occupaient le quart de
/// l'écran sans dire *ce qu'on attend*. Sous le match, la date affichée était
/// celle du pari, présentée comme celle du match. La cote apparaissait deux
/// fois, la confiance en bleu « information », et la page ne menait nulle
/// part : ni au match, ni à son analyse.
///
/// ── Ce qu'elle est ───────────────────────────────────────────────────────
///
///   · l'en-tête dit où en est le pari : coup d'envoi dans 5 h, match en
///     cours et son score, ou — une fois réglé — le résultat net, en grand ;
///   · le match porte ses écussons, son coup d'envoi, et s'ouvre au toucher ;
///   · l'argent : ce qu'on gagne si c'est bon, ce qu'on perd sinon, côte à
///     côte, et le retour total en dessous.
class BetDetailPage extends StatelessWidget {
  final BankrollBet bet;
  const BetDetailPage({super.key, required this.bet});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;

    return Scaffold(
      backgroundColor: cl.bg,
      appBar: AppBar(
        backgroundColor: cl.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr(context, "Détail du pari"),
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _EnTeteStatut(bet: bet).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 12),

          // ── Mise réelle, au résultat (M1) ─────────────────────────────────
          if (bet.aConfirmer) ...[
            ConfirmationMise(bet: bet),
            const SizedBox(height: 12),
          ],

          _CarteMatch(bet: bet)
              .animate().fadeIn(duration: 350.ms, delay: 80.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 12),
          _CartePronostic(bet: bet)
              .animate().fadeIn(duration: 350.ms, delay: 150.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 12),
          _CarteArgent(bet: bet)
              .animate().fadeIn(duration: 350.ms, delay: 220.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 20),

          // La page menait nulle part : l'analyse est à un toucher.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/pronostics/${bet.pronosticId}'),
              icon: const Icon(Icons.analytics_outlined, size: 18),
              label: Text(bet.matchStatus == 'finished'
                  ? tr(context, "Voir le match")
                  : tr(context, "Voir l'analyse du match")),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── En-tête : où en est le pari ───────────────────────────────────────────────

class _EnTeteStatut extends StatelessWidget {
  final BankrollBet bet;
  const _EnTeteStatut({required this.bet});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final (couleur, icone, statut) = switch (bet.result) {
      'WIN'  => (cl.success, Icons.emoji_events_rounded, tr(context, "Gagné")),
      'LOSS' => (cl.error, Icons.close_rounded, tr(context, "Perdu")),
      'PUSH' => (cl.info, Icons.replay_rounded, tr(context, "Remboursé")),
      _      => (cl.warning, Icons.hourglass_empty_rounded, tr(context, "En attente")),
    };
    final regle = bet.result != null;

    // Réglé : le résultat net est l'information qu'on vient chercher.
    final detail = regle
        ? (bet.result == 'PUSH'
            ? tr(context, "Mise remboursée")
            : '${montantSigne(bet.profit ?? 0)} ${nomDevise(bet.currency)}')
        : _contexteAttente(context);

    return Semantics(
      container: true,
      label: [statut, ?detail].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: couleur.withValues(alpha: 0.30)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: couleur.withValues(alpha: 0.15)),
            child: Icon(icone, color: couleur, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(statut, style: TextStyle(color: couleur, fontSize: 14, fontWeight: FontWeight.w800)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail,
                  style: regle
                      ? TextStyle(color: couleur, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)
                      : TextStyle(color: cl.textS, fontSize: 13)),
              ],
              const SizedBox(height: 4),
              Text(tr(context, "Pari placé le {arg0}", [_dateHeure(bet.createdAt)]),
                style: TextStyle(color: cl.textM, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Ce qu'on attend : le coup d'envoi, la fin du match, ou le règlement.
  String? _contexteAttente(BuildContext context) {
    if (bet.matchStatus == 'live') {
      final score = bet.homeScore != null && bet.awayScore != null
          ? ' · ${bet.homeScore} – ${bet.awayScore}' : '';
      return '${tr(context, "Match en cours")}$score';
    }
    if (bet.matchStatus == 'finished') return tr(context, "Match terminé, résultat en cours de calcul");
    final debut = bet.matchDate;
    if (debut == null) return null;
    final reste = debut.difference(DateTime.now());
    if (reste.isNegative) return null;
    if (reste.inHours < 24) {
      final h = reste.inHours, m = reste.inMinutes.remainder(60);
      final duree = h > 0 ? tr(context, "{arg0} h {arg1}", [h, m.toString().padLeft(2, '0')])
                          : tr(context, "{arg0} min", [m]);
      return tr(context, "Coup d'envoi dans {arg0}", [duree]);
    }
    return tr(context, "Coup d'envoi le {arg0}", [_dateHeure(debut)]);
  }
}

// ─── Le match ───────────────────────────────────────────────────────────────────

class _CarteMatch extends StatelessWidget {
  final BankrollBet bet;
  const _CarteMatch({required this.bet});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final aScore = bet.homeScore != null && bet.awayScore != null &&
        (bet.matchStatus == 'live' || bet.matchStatus == 'finished');
    final debut = bet.matchDate;

    Widget equipe(String nom, String? logo) => Expanded(
      child: Column(children: [
        TeamLogoWidget(url: logo, size: 44),
        const SizedBox(height: 8),
        Text(nom,
          textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cl.textP, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
    );

    return Semantics(
      button: true,
      label: tr(context, "{arg0} contre {arg1}, {arg2}. Ouvrir le match.", [bet.homeTeam, bet.awayTeam, bet.league]),
      excludeSemantics: true,
      child: Material(
        color: cl.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/pronostics/${bet.pronosticId}'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cl.border, width: 0.5),
            ),
            child: Column(children: [
              Row(children: [
                Icon(Icons.emoji_flags_rounded, size: 13, color: cl.textM),
                const SizedBox(width: 5),
                Expanded(child: Text(bet.league,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cl.textM, fontSize: 12))),
                Icon(Icons.chevron_right_rounded, color: cl.textM, size: 20),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                equipe(bet.homeTeam, bet.homeTeamLogo),
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 8, right: 8),
                  child: Column(children: [
                    Text(aScore ? '${bet.homeScore} – ${bet.awayScore}'
                                : debut != null ? DateFormat.Hm().format(debut) : 'VS',
                      style: TextStyle(
                        color: bet.matchStatus == 'live' ? cl.error : cl.textP,
                        fontSize: aScore ? 22 : 18, fontWeight: FontWeight.w900)),
                    if (debut != null) ...[
                      const SizedBox(height: 4),
                      // La date du match — la fiche montrait celle du pari.
                      Text(DateFormat.MMMEd().format(debut),
                        style: TextStyle(color: cl.textM, fontSize: 11)),
                    ],
                  ]),
                ),
                equipe(bet.awayTeam, bet.awayTeamLogo),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Le pronostic ───────────────────────────────────────────────────────────────

class _CartePronostic extends StatelessWidget {
  final BankrollBet bet;
  const _CartePronostic({required this.bet});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final pct = bet.pourcentageConfiance;
    // L'échelle de couleur de la confiance, comme partout : elle était ici
    // en bleu « information ».
    final couleur = ConfidenceIndicator.colorFor(context, MatchEntity.niveauDepuisPourcentage(pct));
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _RowLabel(icon: Icons.auto_awesome_rounded, label: tr(context, "Pronostic choisi")),
        const SizedBox(height: 10),
        Text(bet.displayPredictionLabel,
          style: TextStyle(color: cl.textP, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
        if (pct > 0) ...[
          const SizedBox(height: 10),
          // La cote n'est plus répétée ici : elle est dans le calcul.
          _Chip(
            label: tr(context, "Indice de confiance {arg0}", [MatchEntity.affichageConfiance(pct)]),
            color: couleur,
          ),
        ],
      ]),
    );
  }
}

// ─── L'argent ───────────────────────────────────────────────────────────────────

class _CarteArgent extends StatelessWidget {
  final BankrollBet bet;
  const _CarteArgent({required this.bet});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final devise = nomDevise(bet.currency);
    final benefice = bet.potentialGain - bet.stakedAmount;

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _RowLabel(icon: Icons.account_balance_wallet_rounded, label: tr(context, "Financier")),
        const SizedBox(height: 14),
        _LigneCalcul(libelle: tr(context, "Mise"), montant: '${montantExact(bet.stakedAmount)} $devise'),
        const SizedBox(height: 8),
        _LigneCalcul(libelle: tr(context, "Cote"), montant: '× ${bet.oddsUsed.toStringAsFixed(2)}', attenue: true),
        const SizedBox(height: 12),

        if (bet.result == null) ...[
          // Les deux issues côte à côte : ce qu'on risque se lit aussi vite
          // que ce qu'on espère.
          Row(children: [
            Expanded(child: _Issue(
              libelle: tr(context, "Si gagné"),
              montant: '${montantSigne(benefice)} $devise',
              couleur: cl.success,
            )),
            const SizedBox(width: 10),
            Expanded(child: _Issue(
              libelle: tr(context, "Si perdu"),
              montant: '${montantSigne(-bet.stakedAmount)} $devise',
              couleur: cl.error,
            )),
          ]),
          const SizedBox(height: 10),
          // Le retour total, mise comprise — ce que l'opérateur affiche.
          Text(tr(context, "Retour total si gagné : {arg0}", ['${montantExact(bet.potentialGain)} $devise']),
            style: TextStyle(color: cl.textM, fontSize: 12)),
        ] else ...[
          Container(height: 1, color: cl.border),
          const SizedBox(height: 12),
          _LigneCalcul(
            libelle: tr(context, "Résultat net"),
            montant: bet.result == 'PUSH'
                ? tr(context, "Mise remboursée")
                : '${montantSigne(bet.profit ?? 0)} $devise',
          ),
          if (bet.result == 'WIN') ...[
            const SizedBox(height: 8),
            _LigneCalcul(
              libelle: tr(context, "Retour"),
              montant: '${montantExact(bet.potentialGain)} $devise',
              attenue: true,
            ),
          ],
        ],
      ]),
    );
  }
}

class _Issue extends StatelessWidget {
  final String libelle, montant;
  final Color couleur;
  const _Issue({required this.libelle, required this.montant, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: couleur.withValues(alpha: 0.30), width: 0.8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(libelle, style: TextStyle(color: context.cl.textS, fontSize: 11.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(montant, style: TextStyle(color: couleur, fontSize: 17, fontWeight: FontWeight.w900)),
      ),
    ]),
  );
}

/// « 1 octobre 2026 à 15h09 ».
String _dateHeure(DateTime d) => trCurrent("{arg0} à {arg1}h{arg2}", [
      DateFormat.yMMMMd().format(d),
      d.hour.toString().padLeft(2, '0'),
      d.minute.toString().padLeft(2, '0'),
    ]);

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
      const SizedBox(width: 12),
      Flexible(
        child: Text(montant,
          textAlign: TextAlign.end,
          style: TextStyle(
            color: attenue ? context.cl.textM : context.cl.textP,
            fontSize: attenue ? 13 : 14.5,
            fontWeight: attenue ? FontWeight.w600 : FontWeight.w700)),
      ),
    ],
  );
}
