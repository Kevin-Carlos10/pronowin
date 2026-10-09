import 'package:pronowin/l10n/app_strings.dart';

/// Le calcul statistique et l'analyste, mis face à face.
///
/// La fiche d'un match affichait deux pourcentages sans les relier : « indice
/// de confiance 85 % » sur le pronostic, « probabilité de succès 58 % » dans
/// l'analyse, quelques centimètres plus bas. Vu en test sur France – Belgique.
/// Les deux sont légitimes — l'un est l'avis de l'analyste, l'autre un calcul
/// fondé sur les cotes et la forme —, mais sans un mot pour les relier,
/// l'abonné lit une application qui se contredit, au moment même où il décide
/// de sa mise.
///
/// La phrase dit d'où vient l'écart, et dans quel sens : un calcul plus
/// prudent que l'analyste est une information utile, pas un défaut à cacher.
class AvisCompares {
  /// Probabilité du calcul, 0–100.
  final int calcul;

  /// Indice de confiance de l'analyste, 0–100.
  final int analyste;

  const AvisCompares({required this.calcul, required this.analyste});

  /// En deçà, les deux avis sont considérés comme concordants : quinze points
  /// séparent deux paliers de confiance, et un écart moindre ne change pas la
  /// lecture du pronostic.
  static const int ecartNotable = 15;

  /// Calcul moins analyste, en points.
  int get ecart => calcul - analyste;

  bool get concordants => ecart.abs() < ecartNotable;

  /// Le calcul est-il plus prudent que l'analyste ?
  bool get calculPlusPrudent => !concordants && ecart < 0;

  String get phrase => concordants
      ? trCurrent("Le calcul rejoint l'avis de notre analyste : {arg0} % contre {arg1} %.", [calcul, analyste])
      : calculPlusPrudent
          ? trCurrent("Le calcul, fondé sur les cotes et la forme, est plus prudent que notre analyste : {arg0} % contre {arg1} %.", [calcul, analyste])
          : trCurrent("Le calcul, fondé sur les cotes et la forme, est plus confiant que notre analyste : {arg0} % contre {arg1} %.", [calcul, analyste]);
}
