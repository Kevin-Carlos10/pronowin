/// Nom d'usage d'une devise, par opposition à son code ISO.
///
/// Le Bankroll stocke des codes ISO — c'est la bonne donnée : `XOF` est sans
/// ambiguïté, il voyage bien, il ne dépend d'aucune langue. Mais il était aussi
/// **affiché** tel quel, y compris sur l'écran de confirmation de mise :
///
///     Mise enregistrée !
///     1 500 XOF · Elche – Barcelona
///
/// Or `XOF` est un code bancaire. Ce qui est écrit sur les billets, et ce que
/// les gens disent, c'est « FCFA ». Le reste de l'application l'écrit d'ailleurs
/// ainsi à vingt-sept endroits — le code ISO n'apparaissait qu'ici, précisément
/// au moment où l'utilisateur valide de l'argent.
///
/// On garde donc le code en base et on traduit à l'affichage.
const Map<String, String> _nomsDevises = {
  // Franc CFA d'Afrique de l'Ouest (BCEAO) et d'Afrique centrale (BEAC). Les
  // deux se disent « FCFA » — ils ne sont pas interchangeables à la banque,
  // mais un utilisateur ne voit qu'une seule devise à la fois : la sienne.
  'XOF': 'FCFA',
  'XAF': 'FCFA',
  'GNF': 'GNF',
  'EUR': '€',
};

/// Nom à afficher pour un code de devise. Un code inconnu est rendu tel quel —
/// mieux vaut un sigle que rien.
String nomDevise(String? code) {
  if (code == null || code.isEmpty) return '';
  return _nomsDevises[code.toUpperCase()] ?? code;
}

/// Libellé du sélecteur de devise, qui doit lever l'ambiguïté entre les deux
/// francs CFA — là, et seulement là, le code ISO a sa place.
String libelleChoixDevise(String code) {
  const regions = {'XOF': 'Afrique de l\'Ouest', 'XAF': 'Afrique centrale'};
  final region = regions[code.toUpperCase()];
  final nom = nomDevise(code);
  return region == null ? nom : '$nom · $region';
}
