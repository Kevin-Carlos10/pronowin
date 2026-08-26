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

/// Probabilité d'issue, formulée sans jamais annoncer l'impossible.
///
/// Le fournisseur renvoie parfois « 0 % » pour l'outsider — c'est ce qu'affichait
/// l'écran pour Elche recevant le Barça. Aucun modèle sérieux ne donne zéro
/// chance à une équipe de football : c'est un arrondi, pas une prédiction. Le
/// lire tel quel engage la crédibilité de PronoWin, pas celle d'API-Football.
///
/// « < 1 % » dit la même chose — c'est très peu probable — sans affirmer que
/// c'est exclu. Le cas « aucune donnée » est traité en amont : la barre entière
/// disparaît si les trois issues sont nulles, plutôt que d'afficher trois
/// « < 1 % » qui ne feraient pas 100 %.
String _libellePourcent(double v) => v < 1 ? '< 1 %' : '${v.round()} %';

/// « Pourquoi ce pronostic » — la lecture du match par le modèle statistique.
class _AnalyseModele extends ConsumerWidget {
  final String matchId;
  const _AnalyseModele({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchInsightsProvider(matchId));
    final data  = async.valueOrNull;
    if (data == null || data.comparisons.isEmpty) return const SizedBox.shrink();

    // Sortie inexploitable : la section entière disparaît.
    //
    // Sur Lask Linz – Celtic, le fournisseur donnait 0 % à Lask Linz et 100 %
    // de l'avantage à Celtic sur les cinq critères. Lask Linz a gagné 4–1.
    //
    // Afficher « < 1 % » adoucissait le libellé sans changer le fond : l'écran
    // continuait de présenter une butée numérique comme une lecture du match,
    // sous le titre « Pourquoi ce pronostic ». Mieux vaut ne rien dire — c'est
    // la même règle que le bilan Premium, qui se tait sous dix pronostics
    // tranchés plutôt que d'annoncer 100 % sur trois.
    if (!data.modeleExploitable) return const SizedBox.shrink();

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

        // La conclusion d'abord. La section s'appelle « Pourquoi ce
        // pronostic » : elle ouvrait pourtant sur des barres brutes, en
        // laissant le lecteur assembler lui-même un verdict qui figurait en
        // sixième ligne d'une liste de six.
        _VerdictModele(data: data),
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.lightbulb_outline_rounded,
                    color: AppColors.primary, size: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ce conseil vient du modèle tiers, pas de la rédaction :
                    // il peut différer du pronostic PronoWin affiché plus haut,
                    // et deux recommandations sans étiquette sur le même écran
                    // laissent le lecteur choisir au hasard.
                    Text('Marché suggéré par le modèle',
                      style: TextStyle(
                        color: AppColors.primary, fontSize: 9.5,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    const SizedBox(height: 3),
                    Text(data.advice!,
                      style: TextStyle(
                        color: context.cl.textS, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        _LegendeAxes(data: data),
        const SizedBox(height: 11),
        _AxesComparaison(data: data),

        const SizedBox(height: 12),
        // Le fournisseur n'est plus nommé, mais la distinction reste : ces
        // chiffres viennent d'un modèle tiers, pas d'une mesure de PronoWin.
        // Laisser croire le contraire serait une régression d'honnêteté, pas
        // un simple changement de libellé.
        Text(
          // Les deux sources sont nommées séparément : les pourcentages
          // viennent désormais du marché quand les cotes le permettent, les
          // barres restent la lecture du modèle externe. Les confondre, c'était
          // afficher « < 1 % » à côté d'une cote qui disait 48,5 %.
          data.probabilitesDuMarche
            ? 'Barres : modèle statistique externe — forme, attaque, défense, '
              'confrontations directes et distribution de Poisson.'
            : 'Modèle statistique externe — forme, attaque, défense, '
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

    // Trois issues à zéro, ce n'est pas un match impossible : c'est un modèle
    // qui n'a rien à dire. Mieux vaut ne rien montrer que trois « < 1 % » dont
    // la somme ne ferait pas 100 %.
    if (max <= 0) return const SizedBox.shrink();

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
              label: '$nom : ${_libellePourcent(v)}',
              excludeSemantics: true,
              child: Column(children: [
                Text(_libellePourcent(v),
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

      // Nommer la source des pourcentages.
      //
      // Ils viennent des cotes quand celles-ci sont exploitables : un prix de
      // marché agrège bien plus d'information qu'un modèle bâti sur les seuls
      // buts marqués. Sans cette mention, un lecteur les prendrait pour un
      // calcul maison — et ne saurait pas pourquoi ils diffèrent des barres,
      // qui restent la lecture du modèle externe.
      if (data.probabilitesDuMarche) ...[
        const SizedBox(height: 6),
        Text(
          data.margeBookmaker != null
            ? 'Probabilités du marché, marge de '
              '${decimalFr(data.margeBookmaker!)} % retirée.'
            : 'Probabilités déduites des cotes du marché.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textM, fontSize: 10, height: 1.35)),
      ],
    ]);
  }
}

/// Nom de l'axe qui porte la synthèse pondérée du fournisseur.
const _cleSynthese = 'Synthèse';

/// Verdict du modèle, en une phrase et un chiffre.
///
/// La synthèse était la sixième ligne d'une liste de six, au même poids visuel
/// que « Buts » ou « Confrontations ». C'est pourtant la seule qui réponde à la
/// question posée par le titre de la section. Sortie de la liste, elle devient
/// la conclusion — et les axes deviennent ce qu'ils sont : les pièces qui la
/// soutiennent.
class _VerdictModele extends StatelessWidget {
  final MatchInsights data;
  const _VerdictModele({required this.data});

  @override
  Widget build(BuildContext context) {
    final synthese = data.comparisons
        .where((a) => a.label == _cleSynthese)
        .firstOrNull;
    if (synthese == null) return const SizedBox.shrink();

    // La règle du verdict vit hors du widget : elle décide si l'écran affirme
    // ou non un penchant, ce qui mérite d'être testé plutôt que constaté.
    final verdict = VerdictComparaison(
      domicile:     synthese.home,
      exterieur:    synthese.away,
      nomDomicile:  data.homeTeam,
      nomExterieur: data.awayTeam,
    );

    final accent = verdict.indecis
        ? context.cl.textM
        : (verdict.favoriADomicile ? AppColors.success : AppColors.info);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 0.9),
      ),
      child: Row(children: [
        Icon(verdict.indecis
              ? Icons.balance_rounded
              : Icons.trending_up_rounded,
          color: accent, size: 18),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(verdict.titre,
              style: TextStyle(
                color: verdict.indecis ? context.cl.textP : accent,
                fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.25)),
            const SizedBox(height: 2),
            Text(
              verdict.indecis
                ? 'Avantage réparti à ${synthese.home.round()} / '
                  '${synthese.away.round()} sur l\'ensemble des critères'
                : '${verdict.partFavori} % de l\'avantage sur l\'ensemble '
                  'des critères',
              style: TextStyle(
                color: context.cl.textM, fontSize: 11, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}

/// Légende des deux couleurs, et surtout : ce que mesurent ces nombres.
///
/// Sans elle, « Elche 100 · Barcelona 0 » se lit « Elche est parfait, le Barça
/// est nul » — une absurdité que le reste de l'écran dément aussitôt (cote
/// 9.45 contre 1.35). La donnée n'est pas fausse : c'est une **répartition**
/// de l'avantage entre deux équipes, pas une note absolue. Le lecteur ne
/// pouvait pas le deviner.
class _LegendeAxes extends StatelessWidget {
  final MatchInsights data;
  const _LegendeAxes({required this.data});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _Pastille(couleur: AppColors.success, nom: data.homeTeam),
        const SizedBox(width: 14),
        _Pastille(couleur: AppColors.info, nom: data.awayTeam),
      ]),
      const SizedBox(height: 7),
      Text(
        'Répartition de l\'avantage sur chaque critère : 100 signifie que tout '
        'l\'avantage est d\'un côté, 50-50 qu\'aucune équipe ne se détache.',
        style: TextStyle(color: context.cl.textM, fontSize: 10.5, height: 1.4)),
    ],
  );
}

class _Pastille extends StatelessWidget {
  final Color couleur;
  final String nom;
  const _Pastille({required this.couleur, required this.nom});

  @override
  Widget build(BuildContext context) => Flexible(
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(nom,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.cl.textS, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]),
  );
}

/// Les axes en barres opposées, domicile à gauche, extérieur à droite.
///
/// La synthèse en est exclue : elle est promue en verdict au-dessus, et la
/// répéter ici ferait croire à un septième critère indépendant.
class _AxesComparaison extends StatelessWidget {
  final MatchInsights data;
  const _AxesComparaison({required this.data});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final axe in data.comparisons.where((a) => a.label != _cleSynthese))
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Semantics(
            label: '${axe.label} : ${axe.home.round()} pour cent pour '
                   '${data.homeTeam}, ${axe.away.round()} pour cent pour '
                   '${data.awayTeam}',
            excludeSemantics: true,
            child: Builder(builder: (context) {
              // `>=` mettait le domicile en vert dès l'égalité : un axe à 0/0
              // ou à 50/50 s'affichait comme un avantage qui n'existe pas. Le
              // vert signale un écart, pas une absence de départage.
              final domGagne = axe.home > axe.away;
              final extGagne = axe.away > axe.home;
              return Row(children: [
              SizedBox(
                width: 30,
                child: Text('${axe.home.round()}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: domGagne ? AppColors.success : context.cl.textM,
                    fontSize: 11,
                    fontWeight: domGagne ? FontWeight.w800 : FontWeight.w500)),
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
                    color: extGagne ? AppColors.info : context.cl.textM,
                    fontSize: 11,
                    fontWeight: extGagne ? FontWeight.w800 : FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              // 74 px tronquaient « Modèle de Poisson » — le seul des sept
              // libellés à dépasser. Le libellé est désormais l'élément
              // souple : c'est la barre qui cède de la place, pas le mot.
              SizedBox(
                width: 96,
                child: Text(axe.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
              ),
            ]);
            }),
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
                  // `libelle` porte le seuil quand il existe : « Over 2.5 » et
                  // non « Over ». Sans lui, trois lignes Over/Under
                  // s'affichaient à l'identique, et la cote pouvait se lire
                  // comme un nombre de buts.
                  Text(v.libelle,
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
