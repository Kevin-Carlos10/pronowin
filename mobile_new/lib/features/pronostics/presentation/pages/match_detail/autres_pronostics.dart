// Les autres pronostics du match — plusieurs pronostics par match
// (23 novembre 2026).
//
// `part` et non un fichier autonome : la fiche du match garde ses classes
// privées à la bibliothèque.
part of '../match_detail_page.dart';

/// Les autres pronostics publiés sur ce match, sous le pronostic principal.
///
/// Chacun porte son propre verrou VIP, décidé par le serveur : un pronostic
/// VIP arrive sans son choix, sa cote ni son analyse pour qui n'est pas
/// abonné ; la ligne le dit et mène à l'offre Premium. Son résultat, lui,
/// reste visible, comme celui du principal.
///
/// Sur iPhone, pas de cote (`sansPariProvider`) : la fiche reçoit déjà le
/// match sans cotes (`MatchEntity.sansCotes`), autres pronostics compris.
/// Porte sa propre marge : sans autre pronostic, elle ne laisse pas de trou.
///
/// Depuis le 24 novembre 2026, chaque pronostic ouvert se valide dans la
/// bankroll (avant le coup d'envoi, pas sur iPhone) et se partage en image,
/// comme le principal : la fiche leur passe le match portant ce pronostic
/// (`MatchEntity.avecPronostic`).
class _AutresPronostics extends ConsumerWidget {
  final MatchEntity match;
  /// L'utilisateur a un Premium en cours.
  final bool abonne;
  const _AutresPronostics({required this.match, required this.abonne});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autres = match.autresPronostics;
    if (autres.isEmpty) return const SizedBox.shrink();
    // Comme le principal : la saisie ferme au coup d'envoi, et l'iPhone n'a
    // pas de bankroll.
    final miserOuvert = !ref.watch(sansPariProvider) && match.status == MatchStatus.upcoming;
    return Padding(
      key: const Key('autres-pronostics'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(tr(context, "AUTRES PRONOSTICS"), style: TextStyle(
              color: context.cl.textM, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 1)),
          ),
          const SizedBox(height: 4),
          for (final (i, a) in autres.indexed) ...[
            if (i > 0) Divider(height: 1, color: context.cl.borderSoft),
            _LigneAutrePronostic(
              pronostic: a, match: match,
              // La réponse expurgée ne devient pas lisible grâce à l'état
              // local ; un VIP reste fermé à qui n'est pas abonné.
              verrouille: estVerrouille(
                contenuMasque: a.isLocked,
                estPremium: a.isPremium || a.isLocked,
                utilisateurPremium: abonne,
              ),
              onPremium: () => goToPremium(context, ref),
              miserOuvert: miserOuvert,
            ),
          ],
        ]),
      ),
    );
  }
}

class _LigneAutrePronostic extends StatelessWidget {
  final AutrePronostic pronostic;
  final MatchEntity match;
  final bool verrouille;
  final VoidCallback onPremium;
  final bool miserOuvert;
  const _LigneAutrePronostic({required this.pronostic, required this.match,
    required this.verrouille, required this.onPremium, this.miserOuvert = false});

  /// « Marché : Choix », comme la carte du pronostic principal.
  (String?, String) _marcheEtChoix() {
    final libelle = pronostic.libelle(match);
    final sep = libelle.indexOf(':');
    return sep <= 0
        ? (null, libelle)
        : (libelle.substring(0, sep).trim(), libelle.substring(sep + 1).trim());
  }

  String _verdict(BuildContext context) => switch (pronostic.result) {
    PronosticResult.win  => tr(context, " Pronostic gagnant."),
    PronosticResult.loss => tr(context, " Pronostic perdant."),
    PronosticResult.push => tr(context, " Pronostic remboursé."),
    null                 => '',
  };

  @override
  Widget build(BuildContext context) {
    if (verrouille) return _verrouillee(context);
    final (marche, choix) = _marcheEtChoix();
    final pct = pronostic.pourcentageConfiance;
    final cote = pronostic.oddsRecommended;
    final note = pronostic.analystNote;

    final annonce = tr(context, "Autre pronostic : {arg0}{arg1}.{arg2}{arg3}{arg4}", [
      marche == null ? '' : '$marche, ', choix,
      cote > 0 ? tr(context, " Cote recommandée {arg0}.", [cote.toStringAsFixed(2)]) : '',
      pct >= 1 ? tr(context, " Indice de confiance {arg0}.", [MatchEntity.affichageConfiance(pct)]) : '',
      _verdict(context),
    ]);

    final porteur = match.avecPronostic(pronostic);
    final miser = miserOuvert && cote > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
        label: annonce,
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (marche != null) ...[
                Text(marche.toUpperCase(), style: TextStyle(
                  color: context.cl.accent, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 4),
              ],
              Text(choix, style: TextStyle(
                color: context.cl.textP, fontSize: 16,
                fontWeight: FontWeight.w700, height: 1.25)),
            ])),
            if (cote > 0) ...[
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr(context, "COTE"), style: TextStyle(
                  color: context.cl.textM, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text(cote.toStringAsFixed(2), style: TextStyle(
                  color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ],
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (pronostic.isPremium) const _PastilleVip(),
            if (pct >= 1)
              Text(tr(context, "Confiance {arg0}", [MatchEntity.affichageConfiance(pct)]),
                style: TextStyle(
                  color: ConfidenceIndicator.colorFor(context, MatchEntity.niveauDepuisPourcentage(pct)),
                  fontSize: 12, fontWeight: FontWeight.w700)),
            if (pronostic.result != null) _PastilleResultat(resultat: pronostic.result!),
          ]),
          if (note != null && note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(note.trim(), style: TextStyle(
              color: context.cl.textS, fontSize: 13, height: 1.4)),
          ],
        ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          // Toute la largeur disponible ; le bouton n'en prend que ce qu'il
          // lui faut, et son libellé ne se tronque plus.
          Expanded(
            child: miser
                ? Align(alignment: Alignment.centerLeft,
                    child: _MiserButton(match: porteur, compact: true))
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: tr(context, "Partager ce pronostic"),
            child: Material(
              color: Colors.transparent,
              shape: CircleBorder(side: BorderSide(color: context.cl.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('partager-${pronostic.id}'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showShareSheet(context, porteur);
                },
                child: SizedBox(width: 38, height: 38,
                  child: Icon(Icons.ios_share_rounded, size: 18, color: context.cl.textS)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  /// VIP, sans abonnement : ni choix, ni cote, ni analyse ; le résultat
  /// reste visible. La ligne mène à l'offre Premium.
  Widget _verrouillee(BuildContext context) => Semantics(
    label: tr(context, "Pronostic VIP réservé aux membres Premium.{arg0}", [_verdict(context)]),
    button: true,
    excludeSemantics: true,
    child: InkWell(
      key: Key('autre-prono-verrouille-${pronostic.id}'),
      onTap: () {
        HapticFeedback.lightImpact();
        onPremium();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(Icons.lock_rounded, color: context.cl.textM, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, "Pronostic VIP"), style: TextStyle(
              color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(tr(context, "Réservé aux membres Premium"), style: TextStyle(
              color: context.cl.textM, fontSize: 12)),
          ])),
          if (pronostic.result != null) ...[
            const SizedBox(width: 8),
            _PastilleResultat(resultat: pronostic.result!),
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: context.cl.textM, size: 20),
        ]),
      ),
    ),
  );
}

class _PastilleVip extends StatelessWidget {
  const _PastilleVip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: context.cl.dore.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.workspace_premium_rounded, color: context.cl.dore, size: 13),
      const SizedBox(width: 3),
      Text('VIP', style: TextStyle(
        color: context.cl.dore, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _PastilleResultat extends StatelessWidget {
  final PronosticResult resultat;
  const _PastilleResultat({required this.resultat});

  @override
  Widget build(BuildContext context) {
    final (texte, couleur) = switch (resultat) {
      PronosticResult.win  => (tr(context, "Gagné"), context.cl.success),
      PronosticResult.loss => (tr(context, "Perdu"), context.cl.error),
      PronosticResult.push => (tr(context, "Remboursé"), context.cl.textM),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8)),
      child: Text(texte, style: TextStyle(
        color: couleur, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
