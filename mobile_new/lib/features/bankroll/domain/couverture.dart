/// Couverture d'une mise (26 novembre 2026) — le calcul, côté application.
///
/// Le même que le serveur (`backend/src/services/couverture.ts`) : la fiche
/// du match le refait à la main quand l'abonné saisit la cote de l'évènement
/// inverse qu'on lui propose, qui n'est pas forcément celle lue par le
/// serveur.
///
/// Deux façons de couvrir (27 novembre 2026) :
/// - gain égal : mise × cote ÷ cote inverse, les deux issues rapportent la
///   même chose ;
/// - mise remboursée : mise ÷ (cote inverse − 1), arrondie au-dessus — si
///   l'inverse passe, on récupère sa mise ; si la sélection passe, on garde
///   l'essentiel du gain.
enum StrategieCouverture {
  gainEgal('gain_egal'),
  miseRemboursee('mise_remboursee');

  final String code;
  const StrategieCouverture(this.code);
}

class CouvertureCalculee {
  final double miseCouverture;
  final double gainGaranti;
  final double gainPotentiel;
  final double part;
  /// Le résultat net des deux mises si la sélection passe…
  final double siSelection;
  /// … et si c'est l'inverse.
  final double siInverse;
  const CouvertureCalculee({
    required this.miseCouverture,
    required this.gainGaranti,
    required this.gainPotentiel,
    required this.part,
    this.siSelection = 0,
    this.siInverse = 0,
  });

  /// Le seuil de l'alerte est-il atteint ? Un gain nul ou négatif, jamais.
  bool atteint(int seuilPourcent) =>
      gainGaranti > 0 && gainGaranti >= seuilPourcent / 100 * gainPotentiel - 1e-9;
}

/// L'unité d'une devise : 1 pour le franc CFA, 0,01 pour l'euro.
double pasDeDevise(String? devise) =>
    const ['XOF', 'XAF', 'GNF', 'JPY', 'KRW'].contains((devise ?? '').toUpperCase()) ? 1 : 0.01;

CouvertureCalculee? calculerCouverture(double mise, double cote, double coteInverse,
    {double pas = 1, StrategieCouverture strategie = StrategieCouverture.gainEgal}) {
  if (!(mise > 0 && cote > 1 && coteInverse > 1 && pas > 0)) return null;
  double arrondir(double n) => (n / pas).roundToDouble() * pas;
  final brut = strategie == StrategieCouverture.miseRemboursee
      ? mise / (coteInverse - 1) : mise * cote / coteInverse;
  final miseCouverture = strategie == StrategieCouverture.miseRemboursee
      ? (brut / pas - 1e-9).ceilToDouble() * pas
      : arrondir(brut);
  final siSelection = arrondir(mise * cote - mise - miseCouverture);
  final siInverse = arrondir(miseCouverture * coteInverse - mise - miseCouverture);
  final gainGaranti = siSelection < siInverse ? siSelection : siInverse;
  final gainPotentiel = arrondir(mise * (cote - 1));
  return CouvertureCalculee(
    miseCouverture: arrondir(miseCouverture),
    gainGaranti: gainGaranti,
    gainPotentiel: gainPotentiel,
    part: gainPotentiel > 0 ? gainGaranti / gainPotentiel : 0,
    siSelection: siSelection,
    siInverse: siInverse,
  );
}
