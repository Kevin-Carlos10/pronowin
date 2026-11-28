import 'package:flutter/material.dart';

import '../utils/noms_courts.dart';

/// Un nom d'équipe qui passe à sa forme courte (« Man Utd ») quand le nom
/// complet ne tient pas dans la place donnée, comme dans les listes de
/// Sofascore (10 novembre 2026). Le nom complet reste celui que lisent les
/// lecteurs d'écran.
class NomEquipeAdapte extends StatelessWidget {
  final String nom;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  const NomEquipeAdapte(this.nom, {super.key, this.style, this.maxLines = 1, this.textAlign});

  /// Le texte à afficher dans [largeur] : [nom] s'il tient, sinon son nom
  /// court.
  static String choisir(BuildContext context, String nom, double largeur,
      {TextStyle? style, int maxLines = 1}) {
    final court = nomCourt(nom);
    if (court == nom || !largeur.isFinite) return nom;
    final mesure = TextPainter(
      text: TextSpan(text: nom, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: largeur);
    final deborde = mesure.didExceedMaxLines;
    mesure.dispose();
    return deborde ? court : nom;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final texte = choisir(context, nom, c.maxWidth, style: style, maxLines: maxLines);
    return Text(texte,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: style,
      semanticsLabel: texte == nom ? null : nom);
  });
}
