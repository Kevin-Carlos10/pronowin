/// Ce que la synthèse du modèle permet — et ne permet pas — d'affirmer.
///
/// L'axe `total` du fournisseur agrège les critères avec ses propres
/// pondérations. Il répond à la question posée par le titre « Pourquoi ce
/// pronostic », mais il figurait en sixième ligne d'une liste de six, au même
/// poids visuel que « Buts ».
///
/// Deux règles, et la seconde est la plus importante : **un écart faible n'est
/// pas un penchant.** À 52 contre 48, annoncer « le modèle penche pour X »
/// fabriquerait une conviction que le modèle n'a pas — la même faute que le
/// « 0 % de réussite » ou le « +68 % » corrigés ailleurs, appliquée à un
/// pronostic plutôt qu'à un chiffre.
class VerdictComparaison {
  /// Part de l'avantage attribuée à l'équipe à domicile, 0–100.
  final double domicile;

  /// Part attribuée à l'équipe à l'extérieur.
  final double exterieur;

  final String nomDomicile;
  final String nomExterieur;

  const VerdictComparaison({
    required this.domicile,
    required this.exterieur,
    required this.nomDomicile,
    required this.nomExterieur,
  });

  /// En deçà de cet écart, les deux équipes sont considérées à égalité.
  ///
  /// Dix points sur une répartition en cent : au-dessous, la différence tient
  /// autant au bruit du modèle qu'à un déséquilibre réel.
  static const double ecartMinimal = 10;

  double get ecart => (domicile - exterieur).abs();

  /// Le modèle refuse-t-il de départager ?
  bool get indecis => ecart < ecartMinimal;

  /// L'équipe qui ressort, ou `null` si le modèle n'en désigne aucune.
  String? get favori => indecis
      ? null
      : (domicile > exterieur ? nomDomicile : nomExterieur);

  /// Part de l'équipe favorite, arrondie. `null` quand il n'y a pas de favori.
  int? get partFavori => indecis
      ? null
      : (domicile > exterieur ? domicile : exterieur).round();

  /// Le favori joue-t-il à domicile ? Détermine la couleur employée, qui doit
  /// rester celle de la barre correspondante.
  bool get favoriADomicile => domicile > exterieur;

  /// Phrase de tête, telle qu'elle s'affiche.
  String get titre => indecis
      ? 'Le modèle ne départage pas les deux équipes'
      : 'Le modèle penche pour $favori';
}
