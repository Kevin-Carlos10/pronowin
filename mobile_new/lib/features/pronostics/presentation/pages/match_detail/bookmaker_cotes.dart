import 'package:flutter/material.dart';

import '../../../../../core/config/bookmaker_affiliation.dart';
import '../../../../../core/theme/app_theme.dart';

/// Lequel des deux bandeaux de cotes afficher.
enum BandeauCotes {
  /// Sous la marque du partenaire, chaque cote ouvrant le lien d'affiliation.
  partenaire,

  /// En lecture seule, sans marque et sans lien.
  neutre,
}

/// Un seul bandeau, jamais deux — et jamais aucun.
///
/// Les deux étaient empilés : les mêmes trois valeurs, à quarante pixels
/// d'écart, l'une en lecture seule et l'autre cliquable. La raison était
/// bonne — un appui de travers ne doit pas faire quitter l'application — mais
/// à l'écran cela se lisait comme un défaut d'affichage. Pire : le bandeau du
/// haut portait les cotes du même bookmaker sans son logo ni la mention
/// « 18+ », c'est-à-dire des cotes commerciales présentées comme une donnée
/// neutre.
///
/// ── Pourquoi le neutre ne disparaît pas ────────────────────────────────────
///
/// Le bandeau du partenaire ne s'affiche pas sur les paquets des boutiques —
/// un lien d'affiliation vers un opérateur de paris y est le motif de retrait
/// le plus direct. Il ne s'affiche pas non plus quand aucun partenariat n'est
/// configuré : une marque posée au-dessus de trois tirets serait une publicité
/// déguisée en information.
///
/// Supprimer le bandeau neutre aurait donc vidé l'onglet « Cotes » dans ces
/// deux cas — aucune cote, aucun mot, sur l'onglet qui porte ce nom. Les cotes
/// sont une information légitime ; c'est le lien vers le bookmaker qui ne l'est
/// pas partout.
BandeauCotes bandeauCotes({
  required bool estStore,
  required bool partenaireDisponible,
}) =>
    (!estStore && partenaireDisponible)
        ? BandeauCotes.partenaire
        : BandeauCotes.neutre;

/// Bandeau de cotes du bookmaker partenaire.
///
/// Sur le canal direct, c'est le **seul** bandeau de cotes : il porte le nom
/// du marché, la cote recommandée, la marque du partenaire, et chaque cote
/// ouvre le lien d'affiliation. Ailleurs — boutiques, ou partenariat non
/// configuré — c'est le bandeau neutre qui prend sa place. Voir
/// [bandeauCotes].
///
/// Deux règles tenues ici :
///
///  * **le bandeau ne s'affiche pas sans cote.** Une marque de bookmaker posée
///    au-dessus de trois tirets serait une publicité déguisée en information ;
///  * **la mention légale est solidaire du bandeau.** Elle n'est pas un
///    paramètre qu'un appelant pourrait omettre — une promotion de paris sans
///    « 18+ » expose l'app à un retrait des stores, en plus d'être fautive.
class BookmakerCotes extends StatelessWidget {
  final double coteDomicile;
  final double coteNul;
  final double coteExterieur;

  /// Repère la cote correspondant au pronostic, quand il porte sur le 1X2.
  final int? indiceRecommande;

  /// Le marché coté, écrit au-dessus du bandeau.
  ///
  /// « COTES » seul laissait croire que ces trois valeurs étaient celles du
  /// pronostic ; le nom du marché avait été ajouté au bandeau neutre pour
  /// cette raison. Ce bandeau devenant le seul sur le canal direct, il hérite
  /// de cette mention — sans quoi la correction disparaissait avec lui.
  final String? marche;

  const BookmakerCotes({
    super.key,
    required this.coteDomicile,
    required this.coteNul,
    required this.coteExterieur,
    this.indiceRecommande,
    this.marche,
  });

  bool get _aDesCotes =>
      coteDomicile > 0 || coteNul > 0 || coteExterieur > 0;

  /// Deleguee a la configuration : plusieurs ecrans ouvrent ce meme lien.
  static Future<void> ouvrirLien() => BookmakerAffiliation.ouvrir();

  @override
  Widget build(BuildContext context) {
    if (!_aDesCotes) return const SizedBox.shrink();

    // Sans partenariat configure, ce bandeau annonce une enseigne dont le nom
    // est vide et mene a une ouverture qui ne se produit pas. Il disparait,
    // comme la tuile du taux de reussite quand le serveur n'en publie aucun.
    if (!BookmakerAffiliation.disponible) return const SizedBox.shrink();

    final cotes = [
      ('1', coteDomicile),
      ('X', coteNul),
      ('2', coteExterieur),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (marche != null) ...[
        Text(marche!,
          style: TextStyle(
            color: context.cl.textM, fontSize: 9.5,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 8),
      ],
      // Pas de `Semantics(button: true)` sur ce conteneur : il n'est pas
      // cliquable, seules les pastilles le sont. L'annoncer comme un bouton
      // promettrait à un lecteur d'écran une action qui n'existe pas à cet
      // endroit. Chaque pastille porte donc son propre libellé, et lui seul.
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.5),
        ),
        child: Row(children: [
          const _LogoPartenaire(),
          const SizedBox(width: 10),
          for (var i = 0; i < cotes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _CoteCliquable(
                label: cotes[i].$1,
                valeur: cotes[i].$2,
                recommandee: indiceRecommande == i,
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.info_outline_rounded, size: 12, color: context.cl.textM),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            BookmakerAffiliation.mention,
            style: TextStyle(
                color: context.cl.textM, fontSize: 10.5, height: 1.3),
          ),
        ),
      ]),
    ]);
  }
}

/// Marque du partenaire.
///
/// L'image vient du créatif officiel fourni par le programme d'affiliation.
/// Tant qu'elle n'est pas déposée, on affiche le nom en toutes lettres plutôt
/// qu'une icône cassée — et surtout on ne redessine pas un logo de mémoire.
///
/// Le fond est **blanc**, et ce n'est pas un choix esthétique : le créatif
/// officiel est un lettrage « 1X » bleu marine (#0A2A5E) suivi de « BET » bleu
/// vif, sur transparence. Posé sur un fond marine — ce que faisait cette tuile
/// — le « 1X » se confond avec lui et disparaît purement et simplement. Le logo
/// est dessiné pour un support clair ; c'est donc un support clair qu'il lui
/// faut.
class _LogoPartenaire extends StatelessWidget {
  const _LogoPartenaire();

  /// Rapport du lettrage officiel (≈ 4.65:1). La tuile le respecte, sinon
  /// `BoxFit.contain` laisserait les deux tiers de la hauteur vides et le logo
  /// se réduirait à une ligne de 15 px.
  static const double _largeur = 82;
  static const double _hauteur = 34;

  @override
  Widget build(BuildContext context) => Container(
        width: _largeur,
        height: _hauteur,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          BookmakerAffiliation.logo,
          fit: BoxFit.contain,
          // Le repli garde le fond blanc : deux apparences très différentes
          // selon qu'un fichier est présent ou non rendraient un écran de
          // recette trompeur.
          // Plus `const` : le nom du partenaire vient desormais du serveur.
          errorBuilder: (_, _, _) => Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                BookmakerAffiliation.nom,
                style: TextStyle(
                  color: Color(0xFF0A2A5E),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      );
}

/// Une cote, cliquable, qui ouvre le lien partenaire.
class _CoteCliquable extends StatelessWidget {
  final String label;
  final double valeur;
  final bool recommandee;

  const _CoteCliquable({
    required this.label,
    required this.valeur,
    required this.recommandee,
  });

  @override
  Widget build(BuildContext context) {
    // Une cote absente vaut 0 : l'afficher « 0.00 » et la rendre cliquable
    // reviendrait à promettre un pari qui n'existe pas.
    final absente = valeur <= 0;
    final accent = recommandee ? AppColors.success : context.cl.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: absente ? null : BookmakerCotes.ouvrirLien,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          button: !absente,
          // Le libellé dit ce que l'appui déclenche : quitter l'app pour le
          // bookmaker. « Cote 1, 1.65 » seul laisserait croire à un simple
          // affichage.
          label: absente
              ? 'Cote $label indisponible'
              : 'Cote $label, ${valeur.toStringAsFixed(2)} — '
                'parier sur ${BookmakerAffiliation.nom}',
          // Sans cette exclusion, les deux `Text` de la pastille s'ajoutent au
          // libellé : « Cote 1, 1.65 — parier sur 1xBet, 1, 1.65 ». La valeur
          // est déjà dans la phrase, l'entendre trois fois n'aide personne.
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: accent,
                  width: recommandee ? 1.2 : 0.5),
              color: recommandee
                  ? AppColors.success.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      color: context.cl.textM,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                absente ? '—' : valeur.toStringAsFixed(2),
                style: TextStyle(
                  color: absente
                      ? context.cl.textM
                      : (recommandee ? AppColors.success : context.cl.textP),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

