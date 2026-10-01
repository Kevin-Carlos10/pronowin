// Encarts — tutoriels, favoris, hors ligne, bankroll, série — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _TutorielsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.lightImpact();
      context.push('/tutoriels');
    },
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.cl.info.withValues(alpha: 0.12),
            context.cl.info.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cl.info.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: context.cl.info.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.school_rounded, color: context.cl.info, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // « Apprends à gagner » promettait un résultat. Les tutoriels
          // enseignent une méthode — value bet, bankroll, lecture des cotes —
          // pas une issue. C'était la seule promesse de gain de l'application :
          // tout le reste est rétrospectif, « 12 gagnés sur 18 » étant un fait
          // et non une annonce.
          Text(tr(context, "Apprends la méthode"),
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(tr(context, "Stratégies, value bet, bankroll…"),
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded,
          color: context.cl.info, size: 14),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MES FAVORIS
// ══════════════════════════════════════════════════════════════════════════════
class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favsAsync = ref.watch(favoritesListProvider);

    return favsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                title: tr(context, "Mes favoris"),
                leading: Icon(Icons.bookmark_rounded,
                    color: AppColors.primary, size: 15),
                onMore: null),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final fav = list[i];
                  return _FavoriteTile(fav: fav);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  final Map<String, dynamic> fav;
  const _FavoriteTile({required this.fav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status    = fav['status'] as String? ?? '';
    final isLive    = status == 'live';
    final isFinished = status == 'finished';
    final homeScore = fav['home_score'];
    final awayScore = fav['away_score'];
    final hasScore  = homeScore != null && awayScore != null;
    // Le backend renvoie soit l'id du pronostic soit celui du match (résolu
    // côté serveur pour la navigation détail) — `prono_id` n'a jamais existé
    // dans la réponse, ce qui empêchait tout tap sur une tuile favori.
    final pronoId   = fav['id'] as String?;
    final matchId   = fav['match_id'] as String? ?? '';

    Color borderColor = context.cl.border;
    if (isLive) borderColor = context.cl.error.withValues(alpha: 0.6);
    if (isFinished) borderColor = context.cl.border;

    return GestureDetector(
      onTap: () {
        if (pronoId != null) context.push('/pronostics/$pronoId', extra: null);
      },
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ligue + statut
            Row(
              children: [
                Expanded(
                  child: Text(
                    fav['league'] as String? ?? '',
                    style: TextStyle(color: context.cl.textM, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.cl.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('LIVE',
                        style: TextStyle(
                            color: context.cl.error,
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                // Bouton retirer
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(favorisProvider.notifier).basculerMatch(matchId);
                    ref.invalidate(favoritesListProvider);
                  },
                  child: const Icon(Icons.bookmark_rounded,
                      color: AppColors.primary, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Équipes
            Row(
              children: [
                TeamLogoWidget(url: fav['home_team_logo'] as String?, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fav['home_team'] as String? ?? '',
                    style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                TeamLogoWidget(url: fav['away_team_logo'] as String?, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fav['away_team'] as String? ?? '',
                    style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Score ou heure
            if (hasScore && (isLive || isFinished))
              Text(
                '$homeScore - $awayScore',
                style: TextStyle(
                    color: isLive ? context.cl.error : context.cl.textP,
                    fontSize: 13,
                    fontWeight: FontWeight.w900),
              )
            else if (fav['match_date'] != null)
              Text(
                DateFormat('HH:mm').format(
                    DateTime.tryParse(fav['match_date'] as String) ??
                        DateTime.now()),
                style: TextStyle(color: context.cl.textM, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BANNIÈRE HORS LIGNE (SliverToBoxAdapter)
// ══════════════════════════════════════════════════════════════════════════════
class _SliverOfflineBanner extends ConsumerWidget {
  const _SliverOfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline  = ref.watch(isOnlineProvider);
    final lastSync  = ref.watch(lastPronosSyncProvider);
    final fromCache = ref.watch(isServingFromCacheProvider);

    if (isOnline && !fromCache) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final String message;
    final IconData icon;
    final Color color;

    if (!isOnline) {
      icon  = Icons.wifi_off_rounded;
      color = const Color(0xFFD97706);
      if (lastSync != null) {
        final diff = DateTime.now().difference(lastSync);
        final ago  = diff.inMinutes < 60
            ? tr(context, "il y a {arg0} min", [diff.inMinutes])
            : tr(context, "il y a {arg0}h", [diff.inHours]);
        message = tr(context, "Hors ligne · Données du {arg0}", [ago]);
      } else {
        message = tr(context, "Hors ligne · Aucune donnée en cache");
      }
    } else {
      icon    = Icons.cloud_done_rounded;
      color   = context.cl.success;
      message = tr(context, "Reconnecté · Mise à jour en cours…");
    }

    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: Container(
          key: ValueKey(isOnline),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isOnline)
                GestureDetector(
                  onTap: () {
                    ref.invalidate(pronosticsJourProvider);
                    ref.invalidate(actualitesProvider);
                    ref.invalidate(statsJourProvider);
                  },
                  child: Icon(Icons.refresh_rounded, color: color, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MINI-WIDGET BANKROLL
// ══════════════════════════════════════════════════════════════════════════════
class _BankrollMiniWidget extends ConsumerWidget {
  const _BankrollMiniWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankrollAsync = ref.watch(bankrollProvider);

    return bankrollAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (bankroll) {
        if (bankroll == null) return const SizedBox.shrink();

        // Le résultat net, comme sur l'écran Bankroll. Cette carte affichait
        // `solde − budget` : poser 3 000 sur 100 000 y faisait apparaître
        // « −3 000 » en rouge alors que rien n'était perdu. La page Bankroll
        // avait été corrigée, pas ce résumé — le test ne lisait qu'elle.
        final profit      = bankroll.resultatNet;
        final isProfit    = profit >= 0;
        final profitColor = profit > 0
            ? context.cl.success
            : profit < 0 ? context.cl.error : context.cl.textM;
        final settled     = bankroll.bets.where((b) => b.result != null).toList();
        final wins        = settled.where((b) => b.result == 'WIN').length;
        // Quatrième calcul du même taux dans l'application, et le plus
        // divergent : il divisait par `settled.length`, donc les paris
        // remboursés (PUSH) comptaient au dénominateur — un remboursement
        // faisait baisser le taux de réussite. Et son garde-fou s'arrêtait à
        // zéro : un seul pari gagné affichait « 100% win ».
        //
        // Il a échappé à la garde posée pour les trois autres, qui cherchait
        // le motif exact `/ decisive * 100` : celui-ci s'écrit autrement. Une
        // assertion trop étroite n'accuse rien.
        //
        // `BilanParis` porte la règle : dénominateur sans les PUSH, et
        // silence sous cinq paris tranchés.
        //
        // Le bilan du serveur d'abord : [bankroll.bets] est plafonnée à
        // cinquante lignes, le taux calculé dessus devenait faux au-delà.
        final resume = bankroll.resume;
        final bilanCarte = resume != null
            ? BilanParis(
                suivis:     resume.total,
                gagnes:     resume.gagnes,
                perdus:     resume.perdus,
                rembourses: resume.rembourses,
                tauxBrut:   resume.tauxBrut,
                serie:      0,
              )
            : BilanParis(
                suivis:   bankroll.bets.length,
                gagnes:   wins,
                perdus:   settled.where((b) => b.result == 'LOSS').length,
                tauxBrut: settled.where((b) => b.result != 'PUSH').isEmpty
                    ? 0.0
                    : wins /
                        settled.where((b) => b.result != 'PUSH').length * 100,
                serie:    0,
              );
        final winRate = bilanCarte.taux == null
            ? '—'
            : '${bilanCarte.taux!.toStringAsFixed(0)}%';
        final pending = resume?.enAttente
            ?? bankroll.bets.where((b) => b.result == null).length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.push('/bankroll');
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: context.cl.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: context.cl.success.withValues(alpha: 0.25), width: 0.8),
                boxShadow: [BoxShadow(
                  color: context.cl.success.withValues(alpha: 0.06),
                  blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(children: [

                // Icône wallet
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.degradeSucces,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: context.cl.success.withValues(alpha: 0.3),
                      blurRadius: 8, offset: const Offset(0, 3))]),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 19)),
                const SizedBox(width: 12),

                // Solde
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, "Ma bankroll"), style: TextStyle(
                        color: context.cl.textM, fontSize: 11,
                        fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${_fmt(bankroll.currentBalance)} ${nomDevise(bankroll.currency)}',
                        style: TextStyle(
                            color: context.cl.textP, fontSize: 16,
                            fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  ],
                )),

                // ROI + win rate
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      profit == 0
                          ? Icons.trending_flat_rounded
                          : isProfit
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                      color: profitColor, size: 13),
                    const SizedBox(width: 3),
                    Text('${profit > 0 ? '+' : ''}${_fmt(profit)}',
                        semanticsLabel: '${tr(context, "Résultat net")} '
                            '${profit > 0 ? '+' : ''}${_fmt(profit)}',
                        style: TextStyle(color: profitColor,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    // « — win » ne dit rien du tout.
                    //
                    // Sous le seuil, le taux est retenu ; cette carte est trop
                    // étroite pour en expliquer la raison, et un tiret suivi
                    // de « win » occupe la place sans rien apprendre. On
                    // n'affiche donc rien : l'écran Bankroll, qu'un appui sur
                    // la carte ouvre, porte la phrase complète.
                    if (bilanCarte.taux != null)
                      Text('$winRate win',
                          style: TextStyle(
                              color: context.cl.textM, fontSize: 10)),
                    if (pending > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.cl.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                        child: Text(tr(context, "{arg0} en cours", [pending]),
                            style: TextStyle(
                                color: context.cl.warning, fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ]),

                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: context.cl.textM, size: 18),
              ]),
            ),
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}
