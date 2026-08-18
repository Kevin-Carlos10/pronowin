// Enrichissements API-Football — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester.
//
// Règle commune à tout ce fichier : ce sont des **bonus**. Une erreur du
// fournisseur fait disparaître la section, sans message ni bouton Réessayer —
// on ne demande pas à l'utilisateur de gérer l'indisponibilité d'un contenu
// qu'il n'a pas demandé.
part of '../match_detail_page.dart';

/// « Pourquoi ce pronostic » — la lecture du match par le modèle statistique.
class _AnalyseModele extends ConsumerWidget {
  final String matchId;
  const _AnalyseModele({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchInsightsProvider(matchId));
    final data  = async.valueOrNull;
    if (data == null || data.comparisons.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.insights_rounded,
                color: AppColors.primary, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Pourquoi ce pronostic',
              style: TextStyle(
                color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),

        _BarreIssues(data: data),

        if (data.advice != null && data.advice!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.20), width: 0.8)),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.primary, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(data.advice!,
                  style: TextStyle(
                    color: context.cl.textS, fontSize: 12, height: 1.35)),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        _AxesComparaison(data: data),

        const SizedBox(height: 12),
        // Le fournisseur n'est plus nommé, mais la distinction reste : ces
        // chiffres viennent d'un modèle tiers, pas d'une mesure de PronoWin.
        // Laisser croire le contraire serait une régression d'honnêteté, pas
        // un simple changement de libellé.
        Text(
          'Modèle statistique externe — forme, attaque, défense, '
          'confrontations directes et distribution de Poisson.',
          style: TextStyle(color: context.cl.textM, fontSize: 10, height: 1.4)),
      ]),
    );
  }
}

/// Les trois issues du match en parts proportionnelles.
class _BarreIssues extends StatelessWidget {
  final MatchInsights data;
  const _BarreIssues({required this.data});

  @override
  Widget build(BuildContext context) {
    final issues = [
      (data.homeTeam, data.percentHome, AppColors.success),
      ('Nul',         data.percentDraw, AppColors.warning),
      (data.awayTeam, data.percentAway, AppColors.info),
    ];
    final max = issues.map((e) => e.$2).reduce((a, b) => a > b ? a : b);

    return Column(children: [
      // Une seule barre segmentée plutôt que trois jauges : la somme fait 100 %,
      // autant le montrer.
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 7,
          child: Row(children: [
            for (final (_, v, c) in issues)
              if (v > 0) Expanded(flex: (v * 10).round(), child: ColoredBox(color: c)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (final (nom, v, c) in issues)
          Expanded(
            child: Semantics(
              label: '$nom : ${v.round()} pour cent',
              excludeSemantics: true,
              child: Column(children: [
                Text('${v.round()} %',
                  style: TextStyle(
                    color: v == max && v > 0 ? c : context.cl.textS,
                    fontSize: 15,
                    fontWeight: v == max && v > 0 ? FontWeight.w800 : FontWeight.w600)),
                const SizedBox(height: 2),
                Text(nom,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
              ]),
            ),
          ),
      ]),
    ]);
  }
}

/// Les sept axes en barres opposées, domicile à gauche, extérieur à droite.
class _AxesComparaison extends StatelessWidget {
  final MatchInsights data;
  const _AxesComparaison({required this.data});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final axe in data.comparisons)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Semantics(
            label: '${axe.label} : ${axe.home.round()} pour cent pour '
                   '${data.homeTeam}, ${axe.away.round()} pour cent pour '
                   '${data.awayTeam}',
            excludeSemantics: true,
            child: Row(children: [
              SizedBox(
                width: 30,
                child: Text('${axe.home.round()}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: axe.home >= axe.away ? AppColors.success : context.cl.textM,
                    fontSize: 11,
                    fontWeight: axe.home >= axe.away ? FontWeight.w800 : FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Row(children: [
                      Expanded(
                        flex: (axe.home * 10).round().clamp(0, 1000),
                        child: const ColoredBox(color: AppColors.success)),
                      Expanded(
                        flex: (axe.away * 10).round().clamp(0, 1000),
                        child: const ColoredBox(color: AppColors.info)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text('${axe.away.round()}',
                  style: TextStyle(
                    color: axe.away > axe.home ? AppColors.info : context.cl.textM,
                    fontSize: 11,
                    fontWeight: axe.away > axe.home ? FontWeight.w800 : FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 74,
                child: Text(axe.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
              ),
            ]),
          ),
        ),
    ],
  );
}

/// Quand une équipe marque — profil de buts par tranche de 15 minutes.
///
/// C'est la donnée qui justifie un pari « but en seconde période » : un profil
/// concentré après la 75ᵉ ne se devine pas depuis un score final.
class _ButsParTranche extends ConsumerWidget {
  final String matchId;
  const _ButsParTranche({required this.matchId});

  static const _tranches = ['0-15', '16-30', '31-45', '46-60', '61-75', '76-90'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(matchInsightsProvider(matchId)).valueOrNull;
    final dom  = data?.goalsByMinuteHome;
    final ext  = data?.goalsByMinuteAway;
    if (data == null || (dom == null && ext == null)) return const SizedBox.shrink();

    final maxi = [
      ...(dom?.values ?? const <int>[]),
      ...(ext?.values ?? const <int>[]),
    ].fold<int>(1, (a, b) => b > a ? b : a);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.schedule_rounded,
                color: AppColors.warning, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Quand marquent-ils ?',
              style: TextStyle(
                color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Buts marqués cette saison, par tranche de 15 minutes',
          style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
        const SizedBox(height: 16),

        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final t in _tranches)
                Expanded(
                  child: Semantics(
                    label: '$t minutes : ${dom?[t] ?? 0} buts pour ${data.homeTeam}, '
                           '${ext?[t] ?? 0} pour ${data.awayTeam}',
                    excludeSemantics: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Colonne(valeur: dom?[t] ?? 0, maxi: maxi,
                                couleur: AppColors.success),
                            const SizedBox(width: 3),
                            _Colonne(valeur: ext?[t] ?? 0, maxi: maxi,
                                couleur: AppColors.info),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(t.split('-')[1],
                          style: TextStyle(color: context.cl.textM, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Legende(couleur: AppColors.success, texte: data.homeTeam),
          const SizedBox(width: 14),
          _Legende(couleur: AppColors.info, texte: data.awayTeam),
        ]),
      ]),
    );
  }
}

class _Colonne extends StatelessWidget {
  final int valeur, maxi;
  final Color couleur;
  const _Colonne({required this.valeur, required this.maxi, required this.couleur});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: maxi == 0 ? 0 : valeur / maxi),
    duration: context.duree(const Duration(milliseconds: 700)),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
      if (valeur > 0)
        Text('$valeur',
          style: TextStyle(color: couleur, fontSize: 9, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Container(
        width: 11,
        // 3 px de socle : une tranche à zéro doit rester visible comme une
        // tranche, pas disparaître de l'axe.
        height: 3 + v * 58,
        decoration: BoxDecoration(
          color: valeur > 0 ? couleur : context.cl.borderS,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
      ),
    ]),
  );
}

class _Legende extends StatelessWidget {
  final Color couleur;
  final String texte;
  const _Legende({required this.couleur, required this.texte});

  @override
  Widget build(BuildContext context) => Flexible(
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Flexible(
        child: Text(texte,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
      ),
    ]),
  );
}

/// Cotes qui suivent le match, avec la variation depuis l'ouverture.
class _CotesEnDirect extends ConsumerWidget {
  final String matchId;
  const _CotesEnDirect({required this.matchId});

  /// Les marchés réellement utiles à un parieur pendant le match. `/odds/live`
  /// en renvoie 37, dont beaucoup de niches (« qui marquera le 10e but »)
  /// qui noieraient l'information.
  static const _marchesUtiles = {
    'Match Winner', 'Asian Handicap', 'Match Goals', 'Both Teams Score',
    'Double Chance', 'Over/Under Line',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(liveOddsProvider(matchId)).valueOrNull;
    if (data == null || data.markets.isEmpty) return const SizedBox.shrink();

    final marches = data.markets
        .where((m) => _marchesUtiles.contains(m.name))
        .toList();
    if (marches.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.25), width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LivePastille(),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Cotes en direct',
              style: TextStyle(
                color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          if (data.elapsed != null)
            Text("${data.elapsed}'",
              style: const TextStyle(
                color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('Elles évoluent avec le match, contrairement aux cotes d\'ouverture.',
          style: TextStyle(color: context.cl.textM, fontSize: 10.5, height: 1.35)),
        const SizedBox(height: 14),

        for (final m in marches) ...[
          Text(m.name.toUpperCase(),
            style: TextStyle(
              color: context.cl.textM, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in m.values.take(6))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.cl.borderSoft, width: 0.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(v.value,
                    style: TextStyle(color: context.cl.textM, fontSize: 10)),
                  const SizedBox(width: 6),
                  Text(v.odd.toStringAsFixed(2),
                    style: TextStyle(
                      color: context.cl.textP, fontSize: 12,
                      fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

/// Point rouge pulsant, réutilisé par la carte de cotes live.
class _LivePastille extends StatefulWidget {
  @override
  State<_LivePastille> createState() => _LivePastilleState();
}

class _LivePastilleState extends State<_LivePastille>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.boucler(_c, reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.4 + 0.6 * _c.value),
        shape: BoxShape.circle),
    ),
  );
}

/// Notes des joueurs après le coup de sifflet final.
class _NotesJoueurs extends ConsumerWidget {
  final String matchId;
  const _NotesJoueurs({required this.matchId});

  static Color _couleurNote(double n) => n >= 8
      ? AppColors.success
      : n >= 7
          ? const Color(0xFF84CC16)
          : n >= 6
              ? AppColors.warning
              : AppColors.error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joueurs = ref.watch(playerRatingsProvider(matchId)).valueOrNull;
    if (joueurs == null || joueurs.isEmpty) return const SizedBox.shrink();

    final homme = joueurs.first;
    final suite = joueurs.skip(1).take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.star_rounded, color: AppColors.warning, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Notes des joueurs',
              style: TextStyle(
                color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),

        // L'homme du match en évidence : c'est le seul nom que la plupart des
        // lecteurs retiendront, autant le sortir de la liste.
        Semantics(
          label: 'Homme du match : ${homme.name}, note ${homme.rating}, '
                 '${homme.minutes} minutes jouées',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.22), width: 0.8)),
            child: Row(children: [
              _PhotoJoueur(url: homme.photo, taille: 42),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('HOMME DU MATCH',
                    style: TextStyle(
                      color: AppColors.warning, fontSize: 8.5,
                      fontWeight: FontWeight.w800, letterSpacing: 0.7)),
                  const SizedBox(height: 3),
                  Text(homme.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cl.textP, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    "${homme.minutes} min · ${homme.shots} tir${homme.shots > 1 ? 's' : ''}"
                    "${homme.goals > 0 ? ' · ${homme.goals} but${homme.goals > 1 ? 's' : ''}' : ''}",
                    style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
                ])),
              _Note(valeur: homme.rating, grande: true),
            ]),
          ),
        ),

        const SizedBox(height: 12),
        for (final j in suite)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              label: '${j.name}, note ${j.rating}',
              excludeSemantics: true,
              child: Row(children: [
                _PhotoJoueur(url: j.photo, taille: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(j.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.cl.textS, fontSize: 12)),
                ),
                Text('${j.minutes}′',
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
                const SizedBox(width: 10),
                _Note(valeur: j.rating),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _PhotoJoueur extends StatelessWidget {
  final String? url;
  final double taille;
  const _PhotoJoueur({required this.url, required this.taille});

  @override
  Widget build(BuildContext context) => Container(
    width: taille, height: taille,
    decoration: BoxDecoration(
      color: context.cl.surfaceDeep,
      shape: BoxShape.circle,
      border: Border.all(color: context.cl.borderSoft, width: 0.5)),
    child: ClipOval(
      child: url == null
        ? Icon(Icons.person_rounded, color: context.cl.textM, size: taille * 0.55)
        : Image.network(url!, fit: BoxFit.cover,
            // Le CDN renvoie un 404 pour les joueurs sans photo.
            errorBuilder: (_, _, _) =>
              Icon(Icons.person_rounded, color: context.cl.textM, size: taille * 0.55)),
    ),
  );
}

class _Note extends StatelessWidget {
  final double valeur;
  final bool grande;
  const _Note({required this.valeur, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final c = _NotesJoueurs._couleurNote(valeur);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: grande ? 10 : 7, vertical: grande ? 6 : 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.35), width: 0.8)),
      child: Text(valeur.toStringAsFixed(1),
        style: TextStyle(
          color: c, fontSize: grande ? 16 : 12, fontWeight: FontWeight.w800)),
    );
  }
}
