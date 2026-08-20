/// Écriture des montants — **source unique**.
///
/// Deux fonctions `_formatAmount` cohabitaient, chacune privée à son écran :
///
///   * `bankroll_page.dart` groupait les milliers — `2025` → `2 025` ;
///   * `bet_detail_page.dart` abrégeait — `2025` → `2.0 k`.
///
/// Le même montant se lisait donc différemment selon la page, et c'est la page
/// **« Détail du pari »** — celle qu'on ouvre précisément pour vérifier ses
/// chiffres — qui portait la version arrondie. Un gain potentiel de 2 025 F y
/// devenait « 2.0 k » : 25 F évaporés, sans qu'aucune erreur ne se produise.
///
/// L'abréviation reste légitime là où la place manque vraiment (une jauge, une
/// tuile de tableau de bord) — d'où [montantCourt], explicite. Mais elle ne
/// doit jamais être le comportement par défaut d'un écran qui parle d'argent.
library;

/// Montant exact, milliers séparés par une espace insécable fine.
///
/// `2025` → `2 025`. Aucune décimale : les devises visées (FCFA, GNF) n'en
/// utilisent pas à l'affichage courant, et un centime affiché sur un pari
/// mobile money serait du bruit.
String montantExact(num valeur) {
  final negatif = valeur < 0;
  final chiffres = valeur.abs().round().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    // Espace insécable : « 2 025 » ne doit jamais se couper en fin de ligne.
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(chiffres[i]);
  }
  return negatif ? '-$tampon' : tampon.toString();
}

/// Montant signé : le `+` n'apparaît que sur un gain.
///
/// Utile pour un résultat net, où le signe porte l'information principale.
String montantSigne(num valeur) =>
    valeur > 0 ? '+${montantExact(valeur)}' : montantExact(valeur);

/// Forme abrégée, à réserver aux emplacements réellement contraints.
///
/// Nommée explicitement « court » pour qu'un appelant ne l'utilise jamais par
/// inadvertance sur un écran de détail : perdre des unités doit être un choix
/// assumé, pas un défaut hérité.
String montantCourt(num valeur) {
  final v = valeur.abs();
  if (v < 1000) return montantExact(valeur);
  final milliers = v / 1000;
  final texte = milliers == milliers.roundToDouble()
      ? milliers.toStringAsFixed(0)
      : milliers.toStringAsFixed(1);
  return '${valeur < 0 ? '-' : ''}$texte k';
}
