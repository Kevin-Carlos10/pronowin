// Carrousels — direct et carte héros — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _LiveMatchesCarousel extends StatelessWidget {
  final List<dynamic> matches;
  final bool isPremium;
  const _LiveMatchesCarousel({required this.matches, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    // Même widget de carte que « Pronostics du jour », donc strictement la
    // même taille : elle est portée par _hauteurCarrousel, pas recopiée.
    // La carte gère déjà le direct — bordure rouge, pastille LIVE, score au
    // centre à la place du « VS ».
    return SizedBox(
      height: _hauteurCarrousel(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final match = matches[i] as Map<String, dynamic>;
          final id    = match['id'] as String?;
          return SizedBox(
            width: MediaQuery.of(context).size.width * 0.84,
            child: _PronosticCard(
              prono: match,
              isPremium: isPremium,
              compact: true,
              onTap: id == null
                  ? () {}
                  : () {
                      HapticFeedback.lightImpact();
                      context.push('/pronostics/$id');
                    },
              // Verrouillé : on garde la porte d'entrée Premium d'origine.
              onLockedTap: () {
                HapticFeedback.lightImpact();
                showPremiumGateSheet(context,
                    matchLabel:
                        '${match['home_team'] ?? ''} vs ${match['away_team'] ?? ''}');
              },
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// HERO PRONO CARD (Top prono du jour)
// ══════════════════════════════════════════════════════════════════════════════'
class _HeroPronoCard extends StatelessWidget {
  final Map<String, dynamic> prono;
  final VoidCallback onTap;
  /// Mode teaser pour les non-Premium : le match et la confiance restent
  /// visibles, le pronostic et la cote sont masqués — le tap mène à Premium.
  final bool locked;
  const _HeroPronoCard({required this.prono, required this.onTap, this.locked = false});

  @override
  Widget build(BuildContext context) {
    final conf      = (prono['confidence_score'] as num?)?.toInt() ?? 0;
    final isLive    = (prono['status'] as String? ?? '') == 'live';
    final homeScore = prono['home_score'];
    final awayScore = prono['away_score'];
    final hasScore  = isLive && homeScore != null && awayScore != null;

    // Surface toujours sombre : son contenu lit le thème sombre, sinon les
    // textes et icônes suivent le thème clair et disparaissent sur le bleu nuit.
    return SurfaceSombre(builder: (context) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLive
                ? [const Color(0xFF2A0E0E), const Color(0xFF1C0A0A), const Color(0xFF0A0505)]
                : [const Color(0xFF1C2545), const Color(0xFF0F1A35), const Color(0xFF0A0E1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: isLive
                  ? context.cl.error.withValues(alpha: 0.5)
                  : AppColors.primary.withValues(alpha: 0.4),
              width: 1),
          boxShadow: [
            BoxShadow(
              color: (isLive ? context.cl.error : AppColors.primary).withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Ligue + badge top / live
            Row(
              children: [
                // `Flexible` : un nom de ligue long cède la place au badge
                // au lieu de pousser la rangée hors de la carte (99 px à
                // 360 px et 180 %).
                Flexible(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.cl.surfaceD,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sports_soccer_rounded,
                          color: AppColors.primaryLight, size: 11),
                      const SizedBox(width: 5),
                      Flexible(child: Text(
                        prono['league'] as String? ?? '',
                        style: TextStyle(color: context.cl.textS, fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )),
                    ],
                  ),
                )),
                const SizedBox(width: 8),
                if (isLive)
                  _HeroLiveBadge()
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFB8860B), Color(0xFFFFD700)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child:  Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: Colors.white, size: 11),
                        SizedBox(width: 4),
                        Text(tr(context, "TOP DU JOUR"),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // Équipes + score central
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _HeroTeamLogo(url: prono['home_team_logo'] as String? ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        prono['home_team'] as String? ?? '',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Centre : score si live, sinon VS + heure
                if (hasScore)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _HeroScoreBox(score: homeScore),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('-',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w300)),
                        ),
                        _HeroScoreBox(score: awayScore),
                      ]),
                    ]),
                  )
                else
                  Column(
                    children: [
                      const Text('VS',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(
                        prono['match_date'] != null
                            ? DateFormat('HH:mm').format(
                                DateTime.tryParse(prono['match_date'] as String)?.toLocal() ??
                                    DateTime.now())
                            : '--:--',
                        style: TextStyle(
                            color: context.cl.dore, fontSize: 12),
                      ),
                    ],
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _HeroTeamLogo(url: prono['away_team_logo'] as String? ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        prono['away_team'] as String? ?? '',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Pronostic + Cote + Confiance
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(tr(context, "PRONOSTIC"),
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        locked
                            ?  Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.lock_rounded,
                                    color: Color(0xFFFFD700), size: 15),
                                SizedBox(width: 5),
                                Text(tr(context, "Réservé VIP"),
                                    style: TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                              ])
                            : Text(
                                _teamLabel(prono),
                                style: TextStyle(
                                    color: context.cl.accent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                              ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                       Text(tr(context, "COTE"),
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text(
                        locked
                            ? '?.??'
                            : prono['odds_recommended']
                                    ?.toStringAsFixed(2) ??
                                '',
                        style: TextStyle(
                            color: locked
                                ? AppColors.textMuted
                                : context.cl.success,
                            fontSize: 22,
                            fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: [
                       Text(tr(context, "CONFIANCE"),
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      ConfidenceIndicator(score: conf, showLabel: false),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _HeroTeamLogo extends StatelessWidget {
  final String url;
  const _HeroTeamLogo({required this.url});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: 52);
}

class _HeroScoreBox extends StatelessWidget {
  final dynamic score;
  const _HeroScoreBox({required this.score});
  @override
  Widget build(BuildContext context) => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.cl.error.withValues(alpha: 0.4)),
    ),
    alignment: Alignment.center,
    child: Text('$score',
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
  );
}

class _HeroLiveBadge extends StatefulWidget {
  @override
  State<_HeroLiveBadge> createState() => _HeroLiveBadgeState();
}

class _HeroLiveBadgeState extends State<_HeroLiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_pulse, reverse: true);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: context.cl.error.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.cl.error.withValues(alpha: 0.5)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: context.cl.error.withValues(alpha: 0.4 + 0.6 * _pulse.value),
            shape: BoxShape.circle,
          ),
        ),
      ),
      const SizedBox(width: 5),
       Text(tr(context, "EN DIRECT"),
          style: TextStyle(
              color: context.cl.error,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════'
// CARTE PRONOSTIC
// ══════════════════════════════════════════════════════════════════════════════'
// ══════════════════════════════════════════════════════════════════════════════
// BANDE DE PREUVE — le bilan des 30 derniers jours
// ══════════════════════════════════════════════════════════════════════════════
/// Une app de pronostics demande de la confiance ; celle-ci doit être méritée
/// avant tout le reste. Le bilan vivait dans la page Performance, enterrée dans
/// l'onglet Compte : personne ne le voyait.
