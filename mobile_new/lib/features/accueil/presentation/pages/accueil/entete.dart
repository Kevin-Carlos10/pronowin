// En-tête, statistiques rapides et bandeau Premium — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _SliverHeader extends ConsumerWidget {
  final dynamic user;
  final bool isPremium;
  const _SliverHeader({required this.user, required this.isPremium});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now         = DateTime.now();
    final unreadCount = ref.watch(unreadCountProvider);
    final greeting = now.hour < 12
        ? 'Bonjour'
        : now.hour < 18
            ? 'Bon après-midi'
            : 'Bonsoir';

    return SliverAppBar(
      // Mesuré : le contenu (logo, salutation, ligne d'abonnement) occupe
      // environ 130. Les 34 px restants laissaient une bande vide visible.
      expandedHeight: 140,
      // Onglet racine : aucune page à quitter. Sans ça Flutter ajoute une
      // flèche de retour, qui venait se superposer au logo.
      automaticallyImplyLeading: false,
      floating: true,
      pinned: false,
      snap: true,
      elevation: 0,
      backgroundColor: context.cl.bg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.cl.bg, context.cl.surfaceD],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Ligne 1 : Logo PronoWin + cloche (style FotMob) ──────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(text: 'Prono', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Win',   style: TextStyle(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: unreadCount > 0
                        ? 'Notifications, $unreadCount non lues'
                        : 'Notifications',
                    child: GestureDetector(
                    // Zone tactile portée à 48 px (le visuel reste à 38) :
                    // c'est le minimum recommandé par Material.
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/notifications'),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(width: 48, height: 48),
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: context.cl.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.cl.border, width: 0.5),
                          ),
                          child: Icon(Icons.notifications_rounded,
                              color: context.cl.textS, size: 20),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: -4, right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: context.cl.bg, width: 1.5),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Ligne 2 : Avatar + salutation ────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: 'Mon compte',
                    excludeSemantics: true,
                    child: GestureDetector(
                    onTap: () => context.push('/compte'),
                    child: Container(
                      width: 48, height: 48,
                      alignment: Alignment.center,
                      child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Color(0x59E8541A), blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (user?.avatarUrl != null && (user!.avatarUrl as String).isNotEmpty)
                            ? Image.network(
                                user!.avatarUrl as String,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _AvatarInitials(user: user),
                              )
                            : _AvatarInitials(user: user),
                      ),
                    ),
                    ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          // « Parieur_5TQQC » est un pseudo généré, pas un
                          // prénom : mieux vaut ne saluer personne que saluer
                          // une chaîne de caractères.
                          _estPseudoGenere(user?.displayName)
                              ? '$greeting 👋'
                              : '$greeting, ${user?.displayName} 👋',
                          style: TextStyle(
                            color: context.cl.textP,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFB8860B),
                                Color(0xFFFFD700),
                              ]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.workspace_premium_rounded,
                                    color: Colors.white, size: 10),
                                SizedBox(width: 3),
                                Text('PREMIUM',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            // `/abonnement` n'a jamais existé dans la table de
                            // routage : ce bouton — le premier appel à
                            // l'abonnement que voit un compte gratuit, en haut
                            // de l'accueil — ouvrait la page d'erreur du
                            // routeur.
                            //
                            // `goToPremium` plutôt qu'un chemin corrigé : il
                            // passe d'abord par la complétion du profil quand
                            // elle manque, ce qu'un `context.go` direct saute.
                            onTap: () => goToPremium(context, ref),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Plan Gratuit · ',
                                    style: TextStyle(color: context.cl.textM, fontSize: 11)),
                                const Text('Passer Premium ✨',
                                    style: TextStyle(
                                        color: AppColors.primaryLight,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }
}

// ─── Avatar initiales ─────────────────────────────────────────────────────────
class _AvatarInitials extends StatelessWidget {
  final dynamic user;
  const _AvatarInitials({required this.user});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      user?.pseudo?.isNotEmpty == true ? (user!.pseudo as String)[0].toUpperCase() : 'P',
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════'
// NUDGE PSEUDO — invite à remplacer le pseudo auto-généré
// ══════════════════════════════════════════════════════════════════════════════'
class _PseudoNudge extends StatefulWidget {
  final dynamic user;
  const _PseudoNudge({required this.user});

  @override
  State<_PseudoNudge> createState() => _PseudoNudgeState();
}

class _PseudoNudgeState extends State<_PseudoNudge> {
  static const _prefKey = 'pseudo_nudge_dismissed';
  bool _dismissed = true; // caché tant que la préférence n'est pas lue

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _dismissed = p.getBool(_prefKey) ?? false);
    });
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    SharedPreferences.getInstance().then((p) => p.setBool(_prefKey, true));
  }

  @override
  Widget build(BuildContext context) {
    final pseudo = widget.user?.displayName as String? ?? '';
    final isAutoGenerated = pseudo.startsWith('Parieur_') || pseudo == 'Parieur';
    if (_dismissed || !isAutoGenerated) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/compte/edit'),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choisis ton pseudo',
                      style: TextStyle(
                          color: context.cl.textP,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Personnalise ton profil — plus sympa pour tes parrainages !',
                      style: TextStyle(color: context.cl.textM, fontSize: 11)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, color: context.cl.textM, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// STATS RAPIDES
// ══════════════════════════════════════════════════════════════════════════════'
class _QuickStats extends ConsumerWidget {
  final bool isPremium;
  const _QuickStats({required this.isPremium});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsJourProvider);

    return statsAsync.when(
      loading: () => Row(children: [
        _StatChipSkeleton(), const SizedBox(width: 10),
        _StatChipSkeleton(), const SizedBox(width: 10),
        _StatChipSkeleton(),
      ]),
      error: (_, _) => const SizedBox.shrink(),
      data: (stats) {
        final winRate      = stats['winRate']      as int? ?? 0;
        final streak       = stats['streak']       as int? ?? 0;
        final upcoming     = stats['upcoming']     as int? ?? 0;
        final totalFinished = stats['totalFinished'] as int? ?? 0;

        // Nouvel utilisateur sans aucune donnée : ne rien afficher plutôt
        // que trois tuiles « — » qui n'apportent rien.
        if (streak == 0 && totalFinished < 3 && upcoming == 0) {
          return const SizedBox.shrink();
        }

        return Row(children: [
          _StatChip(
            icon: Icons.local_fire_department_rounded,
            label: 'Série',
            // Pas d'emoji ici : la carte porte déjà l'icône flamme, et les
            // deux voisines n'affichent qu'un nombre.
            value: streak > 0 ? '$streak' : '—',
            color: AppColors.warning,
            hint: streak == 0 ? 'Pas encore de série en cours' : null,
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.trending_up_rounded,
            label: 'Taux win',
            value: totalFinished >= 3 ? '$winRate%' : '—',
            color: AppColors.success,
            hint: totalFinished < 3 ? 'Disponible après 3 pronos terminés' : null,
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.sports_soccer_rounded,
            label: 'À venir',
            value: upcoming > 0 ? '$upcoming' : '—',
            color: AppColors.info,
            hint: upcoming == 0 ? 'Aucun match programmé' : null,
          ),
        ]);
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  /// Message affiché en tooltip quand la valeur est indisponible (—)
  final String? hint;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = value == '—';
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (isEmpty ? context.cl.border : color).withValues(alpha: isEmpty ? 1.0 : 0.2),
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isEmpty ? context.cl.textM : color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: isEmpty ? context.cl.textM : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  color: context.cl.textM,
                  fontSize: 9,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );

    if (isEmpty && hint != null) {
      chip = Tooltip(
        message: hint!,
        triggerMode: TooltipTriggerMode.tap,
        preferBelow: true,
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.cl.border)),
        textStyle: TextStyle(color: context.cl.textM, fontSize: 11),
        child: chip,
      );
    }

    return Expanded(child: chip);
  }
}

class _StatChipSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 72,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Container(width: 36, height: 12, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 4),
        Container(width: 28, height: 8, decoration: BoxDecoration(
          color: context.cl.borderS, borderRadius: BorderRadius.circular(4))),
      ]),
    ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(reverse: true); })
      .shimmer(duration: 1000.ms, color: context.cl.border.withValues(alpha: 0.5)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// BANNIÈRE PREMIUM
// ══════════════════════════════════════════════════════════════════════════════
class _PremiumBanner extends ConsumerWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pronosAsync = ref.watch(pronosticsJourProvider);
    final statsAsync  = ref.watch(statsJourProvider);

    // Compte ce qui est réellement derrière le paywall aujourd'hui : une
    // promesse chiffrée du jour convainc mieux qu'un catalogue de fonctions.
    final vipList = pronosAsync.whenOrNull(
          data: (list) => list
              .map((e) => e as Map<String, dynamic>)
              .where((p) => p['is_premium'] == true)
              .toList(),
        ) ??
        const <Map<String, dynamic>>[];
    final vipProno = vipList.isEmpty ? null : vipList.first;
    final nbGrosseCote = vipList
        .where((p) => ((p['odds_recommended'] as num?) ?? 0) >= 2)
        .length;

    // Taux de réussite pour le titre contextuel
    final winRate = statsAsync.whenOrNull(
      data: (s) => (s['winRate'] as num?)?.toDouble(),
    );

    final String headline;
    if (winRate != null && winRate >= 70) {
      headline = '${winRate.toStringAsFixed(0)}% de réussite cette semaine';
    } else if (vipList.length > 1) {
      headline = nbGrosseCote > 0
          ? "${vipList.length} pronos VIP aujourd'hui, "
              "dont $nbGrosseCote à cote supérieure à 2"
          : '${vipList.length} pronos VIP réservés aux membres';
    } else if (vipProno != null) {
      headline = 'Accède au pronostic VIP du jour';
    } else {
      headline = 'Analyses détaillées · Cotes exclusives · VIP';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C2545), Color(0xFF0D1530)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 20, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Corps: preview VIP ou illustration ─────────────────────────
              if (vipProno != null)
                _LockedPronoPreview(prono: vipProno)
              else
                const _PremiumIllustration(),

              // ── Pied: headline + CTA ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text('PREMIUM',
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 9, fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Text(headline,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13, fontWeight: FontWeight.w700,
                              height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.45),
                            blurRadius: 10, offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text('Débloquer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedPronoPreview extends StatelessWidget {
  final Map<String, dynamic> prono;
  const _LockedPronoPreview({required this.prono});

  @override
  Widget build(BuildContext context) {
    final homeTeam     = prono['home_team'] as String? ?? '';
    final awayTeam     = prono['away_team'] as String? ?? '';
    final homeLogoUrl  = prono['home_team_logo'] as String?;
    final awayLogoUrl  = prono['away_team_logo'] as String?;
    final predLabel    = (prono['prediction_label'] as String? ?? '').isEmpty
        ? '???'
        : _teamLabel(prono);
    final oddsRec      = (prono['odds_recommended'] as num?)?.toDouble();

    return Stack(
      children: [
        // Fond match
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Column(children: [
                TeamLogoWidget(url: homeLogoUrl, size: 40),
                const SizedBox(height: 6),
                Text(homeTeam,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  const Text('VS',
                    style: TextStyle(
                      color: AppColors.textMuted, fontSize: 16,
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  if (oddsRec != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(oddsRec.toStringAsFixed(2),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
              Expanded(child: Column(children: [
                TeamLogoWidget(url: awayLogoUrl, size: 40),
                const SizedBox(height: 6),
                Text(awayTeam,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
            ],
          ),
        ),

        // Pronostic flouté (BackdropFilter)
        Positioned(
          left: 16, right: 16, bottom: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: AppColors.primary, size: 13),
                    const SizedBox(width: 6),
                    Text(predLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumIllustration extends StatelessWidget {
  const _PremiumIllustration();

  @override
  Widget build(BuildContext context) {
    const tiles = [
      (Icons.query_stats_rounded,    'Analyses stats',    Color(0xFF8B5CF6)),
      (Icons.show_chart_rounded,     'Cotes exclusives',  Color(0xFF10B981)),
      (Icons.workspace_premium_rounded, 'Pronos VIP',     Color(0xFFFFD700)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Row(
        children: tiles.map((t) {
          final (icon, label, color) = t;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: color.withValues(alpha: 0.2), width: 0.5),
              ),
              child: Column(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════'
// CARROUSEL LIVE
// ══════════════════════════════════════════════════════════════════════════════'
