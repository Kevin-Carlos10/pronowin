// Carte de pronostic et ses satellites — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _PronosticCard extends ConsumerWidget {
  final Map<String, dynamic> prono;
  final bool isPremium;
  final VoidCallback onTap;

  /// Variante carrousel : hauteur imposée par le parent, donc on retire les
  /// blocs de bas de carte dont la présence varie d'un match à l'autre
  /// (forme des équipes, compte à rebours) — sinon les cartes déborderaient.
  final bool compact;

  /// Action quand le pronostic est verrouillé. Sans elle la carte est inerte,
  /// ce qui était le comportement des pronostics ; la section « En direct »
  /// s'en sert pour ouvrir la feuille Premium.
  final VoidCallback? onLockedTap;

  const _PronosticCard(
      {required this.prono,
      required this.isPremium,
      required this.onTap,
      this.compact = false,
      this.onLockedTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocked  = (prono['is_premium'] as bool? ?? false) && !isPremium;
    final conf      = (prono['confidence_score'] as num?)?.toInt() ?? 0;
    final status    = prono['status'] as String? ?? '';
    final isFinished = status == 'finished';
    final isLive     = status == 'live';
    final homeScore  = prono['home_score'];
    final awayScore  = prono['away_score'];
    final hasScore   = homeScore != null && awayScore != null;
    final result     = prono['result'] as String?; // 'WIN' | 'LOSS' | null
    final matchId    = prono['match_id'] as String? ?? '';
    final favorites  = ref.watch(favoritesProvider).valueOrNull ?? {};
    final isFav      = favorites.contains(matchId);

    // « Total buts +/- : Plus de 2.5 » → marché discret + choix mis en avant.
    // Même hiérarchie que la carte « Top prono du jour » de cet écran.
    final odds       = (prono['odds_recommended'] as num?)?.toDouble();
    final fullLabel  = _teamLabel(prono);
    final sepIndex   = fullLabel.indexOf(' : ');
    final marketName = sepIndex > 0 ? fullLabel.substring(0, sepIndex) : 'Pronostic';
    final pickName   = sepIndex > 0 ? fullLabel.substring(sepIndex + 3) : fullLabel;

    // Couleur bordure selon résultat
    Color borderColor;
    if (isFinished && result == 'WIN') {
      borderColor = AppColors.success.withValues(alpha: 0.5);
    } else if (isFinished && result == 'LOSS') {
      borderColor = AppColors.error.withValues(alpha: 0.4);
    } else if (isLive) {
      borderColor = AppColors.error.withValues(alpha: 0.5);
    } else if (isLocked) {
      borderColor = context.cl.border;
    } else {
      borderColor = AppColors.primary.withValues(alpha: 0.2);
    }

    // Sans ceci, le lecteur d'écran récite tout le contenu de la carte à la
    // suite : « PROCHAIN MATCH mar. 11 août 16h00 Bodo/Glimt VS UEFA Champions
    // League Union St. Gilloise 07 HEURES ». Un libellé rédigé vaut mieux.
    final annonce = StringBuffer()
      ..write('${prono['home_team']} contre ${prono['away_team']}');
    if (isLive) {
      annonce.write(', en direct');
      if (hasScore) annonce.write(', score $homeScore à $awayScore');
    }
    if (isLocked) {
      annonce.write(', pronostic réservé aux membres Premium');
    } else {
      annonce.write(', pronostic $pickName');
      final c = prono['odds_recommended'] as num?;
      if (c != null) annonce.write(', cote ${c.toStringAsFixed(2)}');
      if (conf > 0) {
        annonce.write(', confiance ${MatchEntity.percentForConfidence(conf)} %');
      }
    }

    return Semantics(
      button: true,
      label: annonce.toString(),
      excludeSemantics: true,
      child: GestureDetector(
      onTap: isLocked ? onLockedTap : onTap,
      child: Container(
        margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Le direct reprend l'habillage de l'ancienne carte dédiée :
          // dégradé, bordure et halo rouges, valeurs à l'identique. Seule la
          // structure interne est désormais partagée avec les pronostics —
          // c'est ce qui garantit une taille de carte identique.
          color: isLive ? null : context.cl.surface,
          gradient: isLive
              ? const LinearGradient(
                  colors: [Color(0xFF1C0A0A), Color(0xFF2A0E0E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isLive
                  ? AppColors.error.withValues(alpha: 0.45)
                  : borderColor,
              width: isLive ? 1 : 0.8),
          boxShadow: isLive
              ? [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment:
              compact ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
          children: [
            // ── Ligne 1 : compétition, horaire, favori ─────────────────────
            Row(
              children: [
                Icon(Icons.sports_soccer_rounded,
                    color: context.cl.textM, size: 12),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    prono['league'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.cl.textM, fontSize: 10),
                  ),
                ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LivePulseDot(),
                        SizedBox(width: 5),
                        Text('LIVE',
                            style: TextStyle(
                                color: AppColors.error,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ],
                    ),
                  )
                else if (prono['match_date'] != null && !isFinished)
                  Text(
                    DateFormat('HH:mm').format(
                        DateTime.tryParse(prono['match_date'] as String)?.toLocal() ??
                            DateTime.now()),
                    style: TextStyle(
                        color: context.cl.textM,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                // Raccourci vers la bankroll : le pronostic et la mise
                // vivaient dans deux modules séparés, l'utilisateur devait
                // ressaisir équipe, marché et cote à la main.
                if (!isLocked && !isFinished && odds != null) ...[
                  const SizedBox(width: 6),
                  Semantics(
                    button: true,
                    label: 'Enregistrer cette mise dans ma bankroll',
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        // Miser suppose une bankroll, donc un compte. On garde
                        // le bouton visible — c'est une accroche — mais le tap
                        // emmène s'inscrire avec un chemin de retour, plutôt
                        // que d'ouvrir une feuille qui échouera. Même motif que
                        // sur la page détail (_MiserButton).
                        if (!ref.read(effectiveLoggedInProvider)) {
                          final id = prono['id'] as String? ?? '';
                          context.push(
                            '/auth/email?from=${Uri.encodeComponent('/pronostics/$id')}');
                          return;
                        }
                        await showMiserDialog(
                          context,
                          ref: ref,
                          pronosticId: prono['id'] as String? ?? '',
                          homeTeam: prono['home_team'] as String? ?? '',
                          awayTeam: prono['away_team'] as String? ?? '',
                          predictionLabel: fullLabel,
                          confidenceScore: conf,
                          oddsRecommended: odds,
                        );
                      },
                      child: Icon(Icons.account_balance_wallet_rounded,
                          color: context.cl.textM, size: 17),
                    ),
                  ),
                ],
                if (matchId.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(favoritesProvider.notifier).toggle(matchId);
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        isFav
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        key: ValueKey(isFav),
                        color: isFav ? AppColors.primary : context.cl.textM,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ── Ligne 2 : les équipes, chacune collée à son écusson ────────
            // Auparavant les deux logos encadraient un bloc de texte central :
            // impossible de savoir quel écusson allait avec quelle équipe.
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          prono['home_team'] as String? ?? '',
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.cl.textP,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      _SmallTeamLogo(
                          url: prono['home_team_logo'] as String? ?? ''),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: (hasScore && (isFinished || isLive))
                      ? _InlineScore(
                          home: homeScore, away: awayScore, isLive: isLive)
                      : Text('VS',
                          style: TextStyle(
                              color: context.cl.textM,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                ),

                Expanded(
                  child: Row(
                    children: [
                      _SmallTeamLogo(
                          url: prono['away_team_logo'] as String? ?? ''),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          prono['away_team'] as String? ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.cl.textP,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Ligne 3 : le panneau pronostic ─────────────────────────────
            // Marché en petit, choix en gros — comme « 1X2 / 2.976 » chez
            // 1xBet, et comme la carte « Top prono du jour » de cet écran.
            if (isFinished && result != null)
              Row(children: [_ResultBadge(result: result)])
            else if (isLocked)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: context.cl.surfaceD,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, color: context.cl.textM, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Pronostic réservé aux membres Premium',
                          style: TextStyle(
                              color: context.cl.textM,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            marketName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.cl.textM,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pickName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                height: 1.2),
                          ),
                        ],
                      ),
                    ),
                    if ((prono['odds_recommended'] as num?) != null) ...[
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          Text('COTE',
                              style: TextStyle(
                                  color: context.cl.textM,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 2),
                          Text(
                            (prono['odds_recommended'] as num)
                                .toStringAsFixed(2),
                            style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 14,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        Text('CONFIANCE',
                            style: TextStyle(
                                color: context.cl.textM,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 2),
                        ConfidenceIndicator(score: conf, width: 44, showLabel: false),
                      ],
                    ),
                  ],
                ),
              ),

            // Prono label sous le score (matchs terminés débloqués)
            if (!compact && isFinished && !isLocked && (prono['prediction_label'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: result == 'WIN'
                            ? AppColors.success.withValues(alpha: 0.10)
                            : result == 'LOSS'
                                ? AppColors.error.withValues(alpha: 0.10)
                                : context.cl.surfaceD,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Prono : ${_teamLabel(prono)}',
                        style: TextStyle(
                          color: result == 'WIN'
                              ? AppColors.success
                              : result == 'LOSS'
                                  ? AppColors.error
                                  : context.cl.textM,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Countdown (< 2h avant le match) ──────────────────────────
            if (!compact && !isFinished && !isLive) ...[
              () {
                final date = DateTime.tryParse(prono['match_date'] as String? ?? '');
                if (date == null) return const SizedBox.shrink();
                final diff = date.difference(DateTime.now());
                if (diff.inMinutes > 0 && diff.inMinutes <= 120) {
                  return _MatchCountdownInline(kickoff: date);
                }
                return const SizedBox.shrink();
              }(),
            ],

            // ── Forme domicile/extérieur ──────────────────────────────────
            if (!compact && !isLocked) ...[
              () {
                final hp = prono['home_form_points'] as int? ?? 0;
                final ap = prono['away_form_points'] as int? ?? 0;
                if (hp == 0 && ap == 0) return const SizedBox.shrink();
                return _FormRow(
                  homeName: prono['home_team'] as String? ?? '',
                  awayName: prono['away_team'] as String? ?? '',
                  homePoints: hp,
                  awayPoints: ap,
                );
              }(),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _InlineScore extends StatelessWidget {
  final dynamic home;
  final dynamic away;
  final bool isLive;
  const _InlineScore({required this.home, required this.away, this.isLive = false});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppColors.error : context.cl.textP;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive
            ? AppColors.error.withValues(alpha: 0.12)
            : context.cl.surfaceD,
        borderRadius: BorderRadius.circular(8),
        border: isLive
            ? Border.all(color: AppColors.error.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        '$home - $away',
        style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final String result;
  const _ResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final isWin = result == 'WIN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isWin
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWin ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isWin ? AppColors.success : AppColors.error,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            isWin ? 'Gagné' : 'Perdu',
            style: TextStyle(
              color: isWin ? AppColors.success : AppColors.error,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallTeamLogo extends StatelessWidget {
  final String url;
  const _SmallTeamLogo({required this.url});
  @override
  Widget build(BuildContext context) =>
      TeamLogoWidget(url: url.isEmpty ? null : url, size: 28);
}

// ══════════════════════════════════════════════════════════════════════════════
// FILTRE PAR LIGUE
// ══════════════════════════════════════════════════════════════════════════════
class _LeagueFilterChips extends StatelessWidget {
  final List<String> leagues;
  final String? selected;

  /// `null` = toutes les ligues. Le parent affecte directement la valeur : il
  /// n'y a plus de bascule implicite « retoucher la puce active pour annuler »,
  /// qui n'était signalée nulle part à l'écran.
  final ValueChanged<String?> onSelect;

  const _LeagueFilterChips(
      {required this.leagues, required this.selected, required this.onSelect});

  Widget _chip(BuildContext context,
      {required String label,
      required bool isSelected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.cl.border,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.cl.textM,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Sortie explicite du filtre, en tête de liste.
          _chip(context,
              label: 'Toutes',
              isSelected: selected == null,
              onTap: () => onSelect(null)),
          ...leagues.map((l) => _chip(context,
              label: l,
              isSelected: l == selected,
              onTap: () => onSelect(l))),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PASTILLE LIVE + CONFIANCE
// ══════════════════════════════════════════════════════════════════════════════
/// Point rouge pulsant de la pastille « LIVE ».
///
/// Isolé dans son propre widget à état : la carte partagée reste sans état, et
/// seul ce point de 6 px se reconstruit à chaque image — pas toute la carte.
class _LivePulseDot extends StatefulWidget {
  final double size;
  const _LivePulseDot({this.size = 6});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pulsation sans fin : coupée si l'utilisateur a réduit les animations.
    // Le point reste alors rouge plein, l'information est la même.
    if (context.animationsReduites) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            // Mêmes bornes d'opacité que l'ancienne carte : 0,4 → 1,0.
            color: AppColors.error.withValues(alpha: 0.4 + 0.6 * _pulse.value),
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// Rendu unique de la confiance sur l'Accueil.
///
/// Trois représentations coexistaient pour la même donnée `confidence_score` :
/// cinq points dessinés en ligne dans le compte à rebours, cinq points +
/// « Excellent » via un widget, et un pourcentage animé sur la carte héros.
/// Le pourcentage l'emporte : c'est le seul lisible sans légende, et c'est la
/// convention déjà retenue ailleurs dans l'app.
///
/// La couleur suit le niveau (vert / orange / rouge) partout — la carte héros
/// affichait un orange fixe même à 95 %.
class _MatchCountdownInline extends StatefulWidget {
  final DateTime kickoff;
  const _MatchCountdownInline({required this.kickoff});
  @override
  State<_MatchCountdownInline> createState() => _MatchCountdownInlineState();
}

class _MatchCountdownInlineState extends State<_MatchCountdownInline> {
  late Timer _t;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = widget.kickoff.difference(DateTime.now());
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = widget.kickoff.difference(DateTime.now());
      if (mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
    });
  }

  @override
  void dispose() { _t.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) return const SizedBox.shrink();
    final h  = _remaining.inHours;
    final m  = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s  = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = h > 0 ? '${h}h $m min' : '$m:$s';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text('Coup d\'envoi dans ', style: TextStyle(color: context.cl.textM, fontSize: 11)),
          Text(timeStr, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FORME V/N/D (calculée depuis les points sur 5 matchs)
// ══════════════════════════════════════════════════════════════════════════════
class _FormRow extends StatelessWidget {
  final String homeName;
  final String awayName;
  final int homePoints;
  final int awayPoints;
  const _FormRow({required this.homeName, required this.awayName,
      required this.homePoints, required this.awayPoints});

  // Reconstitue une série V/N/D approximative depuis les points (max 15 pts sur 5 matchs)
  List<String> _series(int pts) {
    final list = <String>[];
    var rem = pts;
    for (var i = 0; i < 5; i++) {
      if (rem >= 3) { list.add('V'); rem -= 3; }
      else if (rem >= 1) { list.add('N'); rem -= 1; }
      else { list.add('D'); }
    }
    return list;
  }

  Color _dotColor(String r) =>
    r == 'V' ? AppColors.success : r == 'N' ? AppColors.warning : AppColors.error;

  @override
  Widget build(BuildContext context) {
    final homeSeries = _series(homePoints);
    final awaySeries = _series(awayPoints);
    final total = homePoints + awayPoints;
    final homeAdv = total == 0 ? 0.5 : homePoints / total;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(homeName.split(' ').first,
                  style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              ...homeSeries.map((r) => Container(
                width: 14, height: 14,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: _dotColor(r).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(child: Text(r,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
              )),
              const Spacer(),
              ...awaySeries.map((r) => Container(
                width: 14, height: 14,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: _dotColor(r).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(child: Text(r,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
              )),
              const SizedBox(width: 6),
              Text(awayName.split(' ').first,
                  style: TextStyle(color: context.cl.textM, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: Row(children: [
                Expanded(
                  flex: (homeAdv * 100).round(),
                  child: Container(color: AppColors.primary),
                ),
                Expanded(
                  flex: 100 - (homeAdv * 100).round(),
                  child: Container(color: context.cl.borderS),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avantage domicile ${(homeAdv * 100).round()}%',
                  style: TextStyle(color: context.cl.textM, fontSize: 9)),
              Text('→ ${homeAdv >= 0.5 ? homeName.split(' ').first : awayName.split(' ').first}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION ACTUALITÉS — layout vertical
// ══════════════════════════════════════════════════════════════════════════════
