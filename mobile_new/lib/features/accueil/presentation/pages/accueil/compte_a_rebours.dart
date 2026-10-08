// Compte à rebours du prochain match — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _NextMatchCountdown extends ConsumerStatefulWidget {
  const _NextMatchCountdown();
  @override
  ConsumerState<_NextMatchCountdown> createState() => _NextMatchCountdownState();
}

class _NextMatchCountdownState extends ConsumerState<_NextMatchCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final jourAsync     = ref.watch(pronosticsJourProvider);
    final prochainAsync = ref.watch(nextPronosticProvider);
    final authState = ref.watch(authProvider);
    final userIsPremium = authState is AuthAuthenticated
        ? (authState.user.isPremium)
        : false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Builder(builder: (context) {
          // La carte vedette attend les pronostics du jour : décider avant,
          // c'était montrer le prochain match puis le remplacer par le top
          // une seconde plus tard.
          if (jourAsync.isLoading && !jourAsync.hasValue) return _NextMatchSkeleton();
          final vedette = choisirVedette(
            duJour:   jourAsync.valueOrNull ?? const [],
            prochain: prochainAsync.valueOrNull,
          );
          if (vedette == null) {
            return prochainAsync.isLoading ? _NextMatchSkeleton() : const SizedBox.shrink();
          }
          final prono = vedette.prono;
          final dateStr   = prono['match_date'] as String?;
          if (dateStr == null) return const SizedBox.shrink();
          final matchDate = DateTime.tryParse(dateStr)?.toLocal();
          if (matchDate == null) return const SizedBox.shrink();
          final diff = matchDate.difference(DateTime.now());
          if (diff.isNegative) return const SizedBox.shrink();

          final days    = diff.inDays;
          final hours   = diff.inHours.remainder(24);
          final minutes = diff.inMinutes.remainder(60);
          final seconds = diff.inSeconds.remainder(60);

          final matchId        = prono['id'] as String?;
          final rawPredLabel   = prono['prediction_label'] as String?;
          final predLabel      = (rawPredLabel?.isNotEmpty ?? false) ? _teamLabel(prono) : null;
          final oddsRec        = (prono['odds_recommended'] as num?)?.toDouble();
          final confidenceScore = prono['confidence_score'] as int? ?? 0;
          final isPremium      = prono['is_premium'] as bool? ?? false;
          // Prono premium + utilisateur gratuit → teaser verrouillé :
          // on garde le match et la confiance visibles, on masque le
          // pronostic et la cote, et le tap mène vers Premium.
          final isLocked       = isPremium && !userIsPremium;

          // Surface toujours sombre : son contenu lit le thème sombre, sinon les
          // textes et icônes suivent le thème clair et disparaissent sur le bleu nuit.
          return SurfaceSombre(builder: (context) => GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (isLocked) {
                goToPremium(context, ref);
              } else if (matchId != null) {
                context.push('/pronostics/$matchId');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B1120), Color(0xFF162040), Color(0xFF0B1120)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.8),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 24, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

                // ── Header ──────────────────────────────────────────────────────
                // `Wrap` et non `Row` : à 360 px et 180 %, badge, PREMIUM et
                // date ne tiennent plus sur une ligne (49 px de trop). La
                // date passe alors dessous au lieu de sortir de la carte.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                  // Pourquoi ce match est en tête : le meilleur pronostic du
                  // jour, le prochain à commencer, ou les deux.
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (vedette.estTopDuJour) const _BadgeTopDuJour(),
                    if (vedette.estProchainMatch)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 5, height: 5,
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
                            .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
                            .fadeIn(duration: 600.ms).then().fadeOut(duration: 600.ms),
                          const SizedBox(width: 5),
                           Text(tr(context, "PROCHAIN MATCH"),
                            style: TextStyle(color: context.cl.accent, fontSize: 9,
                              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                        ]),
                      ),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isPremium)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.cl.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                        child: Text('PREMIUM',
                          style: TextStyle(color: context.cl.warning, fontSize: 8,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                    Text(
                      DateFormat("EEE d MMM · HH:mm").format(matchDate),
                      style: TextStyle(color: context.cl.textM, fontSize: 11)),
                  ]),
                ]),
                const SizedBox(height: 16),

                // ── Équipes ──────────────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: Column(children: [
                    TeamLogoWidget(url: prono['home_team_logo'] as String?, size: 52),
                    const SizedBox(height: 7),
                    Text(nomEquipe(prono['home_team'] as String? ?? ''),
                      style: TextStyle(color: context.cl.textP,
                        fontSize: 12, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  ])),
                  // Colonne centrale bornée : le nom de la ligue, sans limite
                  // de largeur, prenait jusqu'à 170 px à 180 % et ne laissait
                  // aux équipes que de quoi écrire « Boru / ssi… ».
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Column(children: [
                        Text('VS',
                          style: TextStyle(color: context.cl.textM, fontSize: 20,
                            fontWeight: FontWeight.w700, letterSpacing: 3)),
                        const SizedBox(height: 4),
                        Text(prono['league'] as String? ?? '',
                          style: TextStyle(color: context.cl.textM, fontSize: 9),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                  Expanded(child: Column(children: [
                    TeamLogoWidget(url: prono['away_team_logo'] as String?, size: 52),
                    const SizedBox(height: 7),
                    Text(nomEquipe(prono['away_team'] as String? ?? ''),
                      style: TextStyle(color: context.cl.textP,
                        fontSize: 12, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  ])),
                ]),
                const SizedBox(height: 16),

                // ── Countdown ────────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 0.5)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    if (days > 0) ...[
                      _CountUnit(value: _pad(days), label: days == 1 ? tr(context, "JOUR") : tr(context, "JOURS")),
                      _CountDivider(),
                    ],
                    _CountUnit(value: _pad(hours), label: tr(context, "HEURES")),
                    _CountDivider(),
                    _CountUnit(value: _pad(minutes), label: 'MIN'),
                    _CountDivider(),
                    _CountUnit(value: _pad(seconds), label: 'SEC'),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Pronostic + confiance + cote ──────────────────────────────────
                if (predLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.12), width: 0.5)),
                    // Deux étages, comme les cartes de liste : sur une seule
                    // ligne, « Vainqueur du match : Dinamo Zagreb » se faisait
                    // tronquer par la confiance et la cote posées à sa droite.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              isLocked
                                  ? Icons.lock_rounded
                                  : Icons.trending_up_rounded,
                              color: isLocked
                                  ? const Color(0xFFFFD700)
                                  : AppColors.primary,
                              size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isLocked ? tr(context, "Réservé VIP") : predLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isLocked
                                      ? const Color(0xFFFFD700)
                                      : context.cl.textP,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25),
                            ),
                          ),
                        ]),

                        if (confidenceScore > 0 || oddsRec != null) ...[
                          const SizedBox(height: 9),
                          Row(children: [
                            if (confidenceScore > 0)
                              ConfidenceIndicator(
                                  pourcentage: MatchEntity.pourcentageDepuisApi(prono),
                                  showLabel: false),
                            const Spacer(),
                            if (oddsRec != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: (isLocked
                                            ? context.cl.textM
                                            : context.cl.success)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8)),
                                // « COTE 1.48 » et non « x1.48 » : le préfixe x
                                // est une convention de multiplicateur, la cote
                                // décimale en est une autre. Une seule des deux.
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(tr(context, "COTE"),
                                        style: TextStyle(
                                            color: context.cl.textM,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.6)),
                                    const SizedBox(width: 5),
                                    Text(
                                        isLocked
                                            ? '?.??'
                                            : oddsRec.toStringAsFixed(2),
                                        style: TextStyle(
                                            color: isLocked
                                                ? context.cl.textM
                                                : context.cl.success,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                          ]),
                        ],
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // ── CTA bouton ────────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.degradeBouton),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.40),
                        blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    // Le pronostic est déjà affiché juste au-dessus ; ce qui
                    // est derrière le bouton, c'est l'analyse.
                    Text(isLocked ? tr(context, "Débloquer avec Premium") : tr(context, "Voir l'analyse"),
                      style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Icon(isLocked ? Icons.lock_open_rounded : Icons.arrow_forward_rounded,
                      color: Colors.white, size: 15),
                  ]),
                ),
              ]),
            ),
          ));
        }),
    );
  }
}

class _NextMatchSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 280,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.cl.borderSoft, width: 0.8)),
    child: Column(children: [
      Row(children: [
        Container(width: 100, height: 18,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(6))),
        const Spacer(),
        Container(width: 80, height: 14,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(6))),
      ]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Column(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(color: context.cl.surfaceD, shape: BoxShape.circle)),
          const SizedBox(height: 8),
          Container(width: 60, height: 12,
            decoration: BoxDecoration(color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(6))),
        ]),
        Container(width: 30, height: 20,
          decoration: BoxDecoration(color: context.cl.surfaceD,
            borderRadius: BorderRadius.circular(4))),
        Column(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(color: context.cl.surfaceD, shape: BoxShape.circle)),
          const SizedBox(height: 8),
          Container(width: 60, height: 12,
            decoration: BoxDecoration(color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(6))),
        ]),
      ]),
      const SizedBox(height: 20),
      Container(height: 52, decoration: BoxDecoration(
        color: context.cl.surfaceD, borderRadius: BorderRadius.circular(14))),
    ]),
  )
    .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
    .shimmer(duration: 1500.ms, color: context.cl.borderSoft.withValues(alpha: 0.5));
}

class _CountUnit extends StatelessWidget {
  final String value, label;
  const _CountUnit({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.5),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 8,
                  letterSpacing: 0.6)),
        ],
      );
}

class _CountDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(':',
            style: TextStyle(
                color: context.cl.accent,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// ERROR CARD
// ══════════════════════════════════════════════════════════════════════════════
class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded,
                color: context.cl.textM, size: 32),
            const SizedBox(height: 8),
            Text(tr(context, "Erreur de connexion"),
                style: TextStyle(color: context.cl.textS)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onRetry, child:  Text(tr(context, "Réessayer"))),
          ],
        ),
      );
}

// ─── BANNIÈRE TUTORIELS ───────────────────────────────────────────────────────


/// « TOP DU JOUR » : le pronostic du jour à l'indice de confiance le plus haut.
///
/// L'ancienne carte « Top prono du jour » portait ce badge en blanc sur un
/// dégradé or : 1,4:1 côté jaune. Ici, l'or du thème sur sa propre teinte.
class _BadgeTopDuJour extends StatelessWidget {
  const _BadgeTopDuJour();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: context.cl.dore.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: context.cl.dore.withValues(alpha: 0.35), width: 0.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, color: context.cl.dore, size: 11),
          const SizedBox(width: 4),
          Text(tr(context, "TOP DU JOUR"),
            style: TextStyle(color: context.cl.dore, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ]),
      );
}
