/// Couverture d'une mise (26 novembre 2026) — le calcul, côté application.
///
/// Le même que le serveur (`backend/src/services/couverture.ts`) : la fiche
/// du match le refait à la main quand l'abonné saisit la cote de l'évènement
/// inverse chez son propre bookmaker, qui n'est pas forcément celle lue par
/// le serveur.
///
/// Mise de couverture = mise × cote ÷ cote inverse : les deux issues
/// rapportent alors la même chose. Le gain garanti est le plus petit des
/// deux, une fois la mise arrondie à l'unité de la devise.
class CouvertureCalculee {
  final double miseCouverture;
  final double gainGaranti;
  final double gainPotentiel;
  final double part;
  const CouvertureCalculee({
    required this.miseCouverture,
    required this.gainGaranti,
    required this.gainPotentiel,
    required this.part,
  });

  /// Le seuil de l'alerte est-il atteint ? Un gain nul ou négatif, jamais.
  bool atteint(int seuilPourcent) =>
      gainGaranti > 0 && gainGaranti >= seuilPourcent / 100 * gainPotentiel - 1e-9;
}

/// L'unité d'une devise : 1 pour le franc CFA, 0,01 pour l'euro.
double pasDeDevise(String? devise) =>
    const ['XOF', 'XAF', 'GNF', 'JPY', 'KRW'].contains((devise ?? '').toUpperCase()) ? 1 : 0.01;

CouvertureCalculee? calculerCouverture(double mise, double cote, double coteInverse, {double pas = 1}) {
  if (!(mise > 0 && cote > 1 && coteInverse > 1 && pas > 0)) return null;
  double arrondir(double n) => (n / pas).roundToDouble() * pas;
  final miseCouverture = arrondir(mise * cote / coteInverse);
  final siSelection = mise * cote - mise - miseCouverture;
  final siInverse = miseCouverture * coteInverse - mise - miseCouverture;
  final gainGaranti = arrondir(siSelection < siInverse ? siSelection : siInverse);
  final gainPotentiel = arrondir(mise * (cote - 1));
  return CouvertureCalculee(
    miseCouverture: miseCouverture,
    gainGaranti: gainGaranti,
    gainPotentiel: gainPotentiel,
    part: gainPotentiel > 0 ? gainGaranti / gainPotentiel : 0,
  );
}
