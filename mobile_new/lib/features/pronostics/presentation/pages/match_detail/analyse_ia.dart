// Analyse statistique et verrou Premium — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _AIAnalysisCard extends ConsumerWidget {
  final String matchId;
  final MatchStatus status;
  const _AIAnalysisCard({required this.matchId, this.status = MatchStatus.upcoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiAsync = ref.watch(aiAnalysisProvider(matchId));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C3AE8).withValues(alpha: 0.08),
            const Color(0xFF3A7BD5).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C3AE8).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6C3AE8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.query_stats_rounded,
              color: Color(0xFF6C3AE8), size: 16),
          ),
          const SizedBox(width: 10),
          Text('Analyse statistique',
            style: TextStyle(
              color: context.cl.textP,
              fontSize: 14,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        aiAsync.when(
          loading: () => _AILoadingState(),
          error: (err, _) {
            final code = err is DioException ? err.response?.statusCode : null;

            // L'endpoint enchaîne authMiddleware PUIS premiumMiddleware : un
            // invité est donc refusé en 401, avant même le test Premium. Ne
            // reconnaître que le 403 lui affichait « Analyse temporairement
            // indisponible » avec un bouton Réessayer qui relançait le même
            // 401 indéfiniment — un mensonge doublé d'une impasse, à l'endroit
            // exact où l'utilisateur veut savoir pourquoi ce pronostic.
            if (code == 401) {
              return _AIPremiumLockedState(
                status: status,
                nonConnecte: true,
                onTap: () => context.push(
                  '/auth/email?from=${Uri.encodeComponent('/pronostics/$matchId')}'),
              );
            }

            final isPremiumRequired = err is DioException &&
                (code == 403 || err.response?.data?['code'] == 'PREMIUM_REQUIRED');
            if (isPremiumRequired) {
              return _AIPremiumLockedState(
                status: status,
                onTap: () => goToPremium(context, ref));
            }
            return _AIErrorState(
              onRetry: () => ref.invalidate(aiAnalysisProvider(matchId)));
          },
          data: (ai) => _AIData(analysis: ai),
        ),
      ]),
    );
  }
}

class _AIData extends StatelessWidget {
  final AiAnalysis analysis;
  const _AIData({required this.analysis});

  Color get _probColor {
    if (analysis.probability >= 70) return AppColors.success;
    if (analysis.probability >= 55) return const Color(0xFF84CC16);
    if (analysis.probability >= 45) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PROBABILITÉ DE SUCCÈS',
              style: TextStyle(
                color: context.cl.textM,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: analysis.probability / 100),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (ctx, val, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: val,
                      minHeight: 8,
                      backgroundColor: ctx.cl.borderSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(_probColor),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: analysis.probability),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, val, _) => Text('$val%',
            style: TextStyle(
              color: _probColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            )),
        ),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✦ ', style: TextStyle(color: Color(0xFF6C3AE8), fontSize: 12)),
          Expanded(
            child: Text(analysis.explanation,
              style: TextStyle(
                color: context.cl.textS,
                fontSize: 12,
                height: 1.5,
              )),
          ),
        ]),
      ),
    ],
  );
}

class _AILoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: const Color(0xFF6C3AE8),
          ),
        ),
        const SizedBox(width: 10),
        Text('Analyse en cours…',
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
      ]),
      const SizedBox(height: 12),
      Container(
        height: 8,
        decoration: BoxDecoration(
          color: context.cl.borderSoft,
          borderRadius: BorderRadius.circular(6)),
      )
        .animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(); })
        .shimmer(duration: 1500.ms, color: const Color(0xFF6C3AE8).withValues(alpha: 0.15)),
    ],
  );
}

class _AIPremiumLockedState extends StatefulWidget {
  final VoidCallback onTap;
  final MatchStatus status;

  /// true = l'utilisateur n'a pas de compte du tout. Le voile et l'aperçu
  /// flouté sont les mêmes — c'est bien du contenu verrouillé — mais on ne lui
  /// vend pas un abonnement avant qu'il ait un compte : on lui propose de
  /// s'inscrire, gratuitement, avec retour sur ce match.
  final bool nonConnecte;

  const _AIPremiumLockedState({
    required this.onTap,
    required this.status,
    this.nonConnecte = false,
  });

  @override
  State<_AIPremiumLockedState> createState() => _AIPremiumLockedStateState();
}

class _AIPremiumLockedStateState extends State<_AIPremiumLockedState>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFDAA520);
  static const _goldLight = Color(0xFFF4C430);

  /// Sur un match terminé, promettre une « probabilité de succès » n'a plus
  /// de valeur : le score est connu. On vend alors le débriefing — ce que
  /// le modèle avait anticipé — qui reste le meilleur moyen de juger sa fiabilité
  /// avant de s'abonner.
  bool get _isFinished => widget.status == MatchStatus.finished;

  String get _title => widget.nonConnecte
    ? 'Crée ton compte pour voir l\'analyse'
    : _isFinished
      ? 'Débriefing du modèle'
      : 'Débloquez l\'analyse complète';

  String get _subtitle => widget.nonConnecte
    ? 'Gratuit, en 30 secondes — tu reviens directement sur ce match'
    : _isFinished
      ? 'Ce que le modèle avait anticipé, et sur quels critères'
      : 'Probabilité de succès calculée à partir des cotes et de la forme';

  String get _cta => widget.nonConnecte
    ? 'Créer mon compte'
    : _isFinished
      ? 'Voir le débriefing'
      : 'Débloquer l\'analyse';

  IconData get _ctaIcon => widget.nonConnecte
    ? Icons.person_add_alt_1_rounded
    : Icons.lock_open_rounded;

  late final AnimationController _pressCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 85),
    reverseDuration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.97).animate(
    CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$_title. $_subtitle',
    excludeSemantics: true,
    child: GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) {
      _pressCtrl.reverse();
      HapticFeedback.lightImpact();
      widget.onTap();
    },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          // Aperçu flouté qui imite une vraie analyse — montre qu'il y a du
          // contenu réel derrière le voile, plutôt qu'une simple phrase.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const Opacity(opacity: 0.55, child: _AIPreviewMock()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.cl.surfaceD.withValues(alpha: 0.55),
                    context.cl.surfaceD.withValues(alpha: 0.93),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_goldLight, _gold]),
                ),
                child: const Icon(Icons.query_stats_rounded, color: Colors.black, size: 19),
              ),
              const SizedBox(height: 10),
              Text(_title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(_subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_goldLight, _gold]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(
                    color: _gold.withValues(alpha: 0.35),
                    blurRadius: 14, offset: const Offset(0, 4))],
                ),
                // Le bouton doré reste identique d'un verrou à l'autre — c'est
                // devenu le signal « action Premium ». Seul le libellé change,
                // pour éviter deux CTA rigoureusement identiques à la suite.
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_ctaIcon, color: Colors.black, size: 15),
                  const SizedBox(width: 6),
                  Text(_cta,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
                ]),
              ).animate(
                  onPlay: (c) {
                    // Scintillement en boucle : coupé si l'utilisateur a réduit
                    // les animations. Le bouton doré reste parfaitement lisible.
                    if (!context.animationsReduites) c.repeat();
                  })
               .shimmer(duration: 2200.ms, delay: 700.ms, color: Colors.white70),
            ]),
          ),
        ]),
      ),
    ),
  ));
}

/// Squelette imitant la mise en page de [_AIData], flouté et assombri
/// derrière le CTA — donne un aperçu crédible du contenu sans afficher
/// de vrais chiffres.
class _AIPreviewMock extends StatelessWidget {
  const _AIPreviewMock();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 8,
              backgroundColor: context.cl.borderSoft,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 34, height: 22,
          decoration: BoxDecoration(
            color: context.cl.borderSoft,
            borderRadius: BorderRadius.circular(5)),
        ),
      ]),
      const SizedBox(height: 16),
      _line(context, 1),
      const SizedBox(height: 7),
      _line(context, 0.85),
      const SizedBox(height: 7),
      _line(context, 0.5),
    ]),
  );

  Widget _line(BuildContext context, double widthFactor) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: Container(
      height: 10,
      decoration: BoxDecoration(
        color: context.cl.borderSoft,
        borderRadius: BorderRadius.circular(4)),
    ),
  );
}

class _AIErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _AIErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.warning_amber_rounded, color: context.cl.textM, size: 16),
    const SizedBox(width: 8),
    Expanded(
      child: Text('Analyse temporairement indisponible.',
        style: TextStyle(color: context.cl.textM, fontSize: 12))),
    TextButton(
      onPressed: onRetry,
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
      child: Text('Réessayer',
        style: TextStyle(color: const Color(0xFF6C3AE8), fontSize: 12))),
  ]);
}

// ─── FORME DES ÉQUIPES ───────────────────────────────────────────────────────

/// Forme récente des deux équipes. Les points de forme n'ont pas de maximum
/// fixe côté backend — ils ne sont exploités qu'en rapport de l'un à l'autre
/// (cf. `formToProb` dans ai_prediction.service.ts) — d'où une barre
/// comparative plutôt que deux jauges sur une échelle absolue.
