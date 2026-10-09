// Forme récente des équipes — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _FormCard extends StatelessWidget {
  final MatchEntity match;
  const _FormCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final total = match.homeFormPoints + match.awayFormPoints;
    final homeRatio = total > 0 ? match.homeFormPoints / total : 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardHeader(
          icon: Icons.trending_up_rounded,
          color: context.cl.success,
          title: tr(context, "Forme des équipes")),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(match.homeTeam,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.cl.success, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(match.awayTeam,
              textAlign: TextAlign.right,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.cl.error, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          Text(tr(context, "{arg0} pts", [match.homeFormPoints]),
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(tr(context, "{arg0} pts", [match.awayFormPoints]),
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: homeRatio),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) => ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(
                  flex: (val * 1000).round().clamp(1, 999),
                  child: Container(color: context.cl.success)),
                Expanded(
                  flex: ((1 - val) * 1000).round().clamp(1, 999),
                  child: Container(color: context.cl.error)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Une issue de match en pastille — V, N, D (W, D, L en anglais) — comme sur
/// Sofascore et 1xBet. La couleur ne porte pas seule l'information : la lettre
/// la redit, et le lecteur d'écran l'énonce en entier.
class _PastilleIssue extends StatelessWidget {
  final IssueMatch issue;
  final double taille;

  /// Le dernier match joué, souligné : une rangée se lit de gauche à droite,
  /// du plus ancien au plus récent, et le trait dit où elle finit.
  final bool dernier;
  const _PastilleIssue(this.issue, {this.taille = 22, this.dernier = false});

  static Color couleur(BuildContext context, IssueMatch i) => switch (i) {
    IssueMatch.victoire => context.cl.success,
    IssueMatch.nul      => context.cl.textM,
    IssueMatch.defaite  => context.cl.error,
  };

  static String lettre(BuildContext context, IssueMatch i) {
    final en = AppStrings.of(context).locale.languageCode == 'en';
    return switch (i) {
      IssueMatch.victoire => en ? 'W' : 'V',
      IssueMatch.nul      => en ? 'D' : 'N',
      IssueMatch.defaite  => en ? 'L' : 'D',
    };
  }

  static String nom(BuildContext context, IssueMatch i) => switch (i) {
    IssueMatch.victoire => tr(context, "Victoire"),
    IssueMatch.nul      => tr(context, "Match nul"),
    IssueMatch.defaite  => tr(context, "Défaite"),
  };

  @override
  Widget build(BuildContext context) {
    final c = couleur(context, issue);
    return Semantics(
      label: nom(context, issue),
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: taille, height: taille,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(taille * 0.3)),
          // Taille fixe : la lettre se réduit plutôt que de déborder quand le
          // texte du téléphone est agrandi.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(lettre(context, issue),
              style: TextStyle(
                color: Colors.white, fontSize: taille * 0.5,
                fontWeight: FontWeight.w700, height: 1))),
        ),
        const SizedBox(height: 3),
        Container(
          width: taille * 0.6, height: 2,
          decoration: BoxDecoration(
            color: dernier ? c : Colors.transparent,
            borderRadius: BorderRadius.circular(1))),
      ]),
    );
  }
}

/// Une rangée de pastilles, de la plus ancienne à la plus récente.
class _RangeeForme extends StatelessWidget {
  final List<IssueMatch> issues;
  final double taille;
  const _RangeeForme(this.issues, {this.taille = 22});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < issues.length; i++) Padding(
        padding: EdgeInsets.only(left: i == 0 ? 0 : taille * 0.18),
        child: _PastilleIssue(issues[i], taille: taille,
          dernier: i == issues.length - 1)),
    ],
  );
}

/// Comparaison simultanée, du plus récent au plus ancien. Les scores gardent
/// l'ordre domicile–extérieur ; la couleur concerne l'équipe de la colonne.
class _FormeRecente extends ConsumerWidget {
  final MatchEntity match;
  const _FormeRecente({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Après le match, la forme actuelle n'est plus celle de l'avant-match.
    final forme = match.status == MatchStatus.finished
        ? null
        : ref.watch(formeRecenteProvider(match.id)).valueOrNull;
    final jauge = match.homeFormPoints > 0 || match.awayFormPoints > 0;
    if (forme == null || forme.vide) {
      return jauge
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _FormCard(match: match),
            )
          : const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('forme-comparaison'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.cl.borderSoft, width: 0.8),
        ),
        child: Column(
          children: [
            Semantics(
              header: true,
              child: Text(
                tr(context, "Forme récente"),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ColonneForme(
                    cle: 'forme-domicile',
                    nom: match.homeTeam,
                    logo: match.homeTeamLogo,
                    matchs: forme.domicile.take(5).toList(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ColonneForme(
                    cle: 'forme-exterieur',
                    nom: match.awayTeam,
                    logo: match.awayTeamLogo,
                    matchs: forme.exterieur.take(5).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, "Plus récent en haut · Scores domicile–extérieur"),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cl.textS, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColonneForme extends StatelessWidget {
  final String cle, nom;
  final String? logo;
  final List<MatchRecent> matchs;
  const _ColonneForme({
    required this.cle,
    required this.nom,
    required this.logo,
    required this.matchs,
  });

  void _ouvrir(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cl.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nom,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cl.textP,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, "Plus récent en haut · Scores domicile–extérieur"),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textS, fontSize: 11),
              ),
              const SizedBox(height: 12),
              for (final m in matchs) _LigneMatchRecent(m),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        key: Key(cle),
        onPressed: matchs.isEmpty ? null : () => _ouvrir(context),
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          foregroundColor: context.cl.textS,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (matchs.isNotEmpty)
              const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
      if (matchs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tr(context, "Aucun match récent connu pour cette équipe."),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 11),
          ),
        )
      else
        for (var i = 0; i < matchs.length; i++)
          _ScoreForme(
            key: Key('$cle-score-$i'),
            m: matchs[i],
            nom: nom,
            logo: logo,
          ),
    ],
  );
}

class _ScoreForme extends StatelessWidget {
  final MatchRecent m;
  final String nom;
  final String? logo;
  const _ScoreForme({super.key, required this.m, required this.nom, this.logo});

  @override
  Widget build(BuildContext context) {
    final gauche = m.domicile ? nom : m.adversaire;
    final droite = m.domicile ? m.adversaire : nom;
    final butsGauche = m.domicile ? m.butsPour : m.butsContre;
    final butsDroite = m.domicile ? m.butsContre : m.butsPour;
    final couleur = switch (m.issue) {
      IssueMatch.victoire => AppColors.fondSucces,
      IssueMatch.nul => const Color(0xFF64748B),
      IssueMatch.defaite => AppColors.fondErreur,
    };
    final date = m.date == null
        ? ''
        : DateFormat.yMMMd(
            AppStrings.of(context).locale.languageCode,
          ).format(m.date!);
    final description =
        '$gauche $butsGauche – $butsDroite $droite. '
        '$nom : ${_PastilleIssue.nom(context, m.issue)}. $date';
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              _TeamLogo(
                url: (m.domicile ? logo : m.adversaireLogo) ?? '',
                size: 24,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Center(child: Container(
                  width: 64,
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: couleur,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$butsGauche - $butsDroite',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(width: 6),
              _TeamLogo(
                url: (m.domicile ? m.adversaireLogo : logo) ?? '',
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un match récent : date, adversaire, terrain, score domicile–extérieur, issue.
class _LigneMatchRecent extends StatelessWidget {
  final MatchRecent m;
  const _LigneMatchRecent(this.m);

  @override
  Widget build(BuildContext context) {
    final langue = AppStrings.of(context).locale.languageCode;
    final terrain = m.domicile ? tr(context, "Domicile") : tr(context, "Extérieur");
    final sousTitre = [terrain, if (m.competition?.isNotEmpty == true) m.competition!].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(38),
          child: Text(
            m.date == null ? '' : DateFormat('dd/MM', langue).format(m.date!),
            style: TextStyle(color: context.cl.textM, fontSize: 11))),
        // L'adversaire ouvre sa fiche, comme dans le classement.
        Expanded(child: LienEquipe(
          nom: m.adversaire, logo: m.adversaireLogo,
          rayon: BorderRadius.circular(8),
          child: Row(children: [
            _TeamLogo(url: m.adversaireLogo ?? '', size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.adversaire,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cl.textP, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(sousTitre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cl.textM, fontSize: 10.5)),
            ])),
          ]),
        )),
        const SizedBox(width: 8),
        Text(m.domicile ? '${m.butsPour}-${m.butsContre}' : '${m.butsContre}-${m.butsPour}',
          style: TextStyle(
            color: _PastilleIssue.couleur(context, m.issue),
            fontSize: 13, fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 10),
        _PastilleIssue(m.issue, taille: 20),
      ]),
    );
  }
}
