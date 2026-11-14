import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Les textes de l'application, à la manière de Threads et d'Instagram
// (8 octobre 2026).
//
// La police était déjà la bonne : celle du système, SF Pro sur iPhone et
// Roboto sur Android, comme ces deux applications. Ce qui distinguait nos
// écrans des leurs, mesuré sur des vidéos côte à côte :
//
//  * la taille — une ligne de liste en 13 pt chez nous, en 17 pt chez Threads
//    (la taille standard d'iOS) ; un texte courant en 13 contre 15 ;
//  * la chasse — Flutter applique celle de Material 3, +0,25 entre chaque
//    lettre, quand iOS resserre sa police système (−0,1 à −0,4 aux tailles de
//    lecture). Nos mots paraissaient étirés ;
//  * l'interligne — 1,43 imposé par Material 3, contre l'interligne naturel
//    de la police chez Apple.

/// De combien nos tailles sont agrandies : 13 → 15,6, 14 → 16,8.
///
/// Les tailles de l'application ont été écrites une à une, près de deux mille
/// fois ; les reprendre toutes aurait mélangé une refonte et des centaines de
/// réglages locaux. Un facteur unique garde leurs proportions — un titre reste
/// plus grand qu'une légende — et les rapproche de celles de Threads.
const double agrandissementTexte = 1.2;

/// L'échelle de texte de l'application : celle du téléphone, appliquée à nos
/// tailles agrandies.
///
/// Le réglage du téléphone garde la main : un utilisateur qui agrandit le
/// texte dans les réglages d'iOS ou d'Android le voit grandir ici aussi. La
/// borne haute reste celle que les bancs de débordement mesurent (1,8) : elle
/// porte sur l'échelle finale, réglage et agrandissement compris.
TextScaler echelleTexte(TextScaler systeme) =>
    _EchelleAgrandie(systeme, agrandissementTexte)
        .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.8);

class _EchelleAgrandie extends TextScaler {
  final TextScaler systeme;
  final double facteur;
  const _EchelleAgrandie(this.systeme, this.facteur);

  // L'échelle du système s'applique à la taille agrandie, pas l'inverse :
  // Android réduit l'agrandissement des grands caractères (échelle non
  // linéaire), et c'est à notre taille réelle qu'il doit le faire.
  @override
  double scale(double fontSize) => systeme.scale(fontSize * facteur);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => systeme.textScaleFactor * facteur;

  @override
  bool operator ==(Object other) =>
      other is _EchelleAgrandie && other.systeme == systeme && other.facteur == facteur;

  @override
  int get hashCode => Object.hash(systeme, facteur);
}

/// Chasse resserrée des textes courants, proche de celle de SF Pro entre 13
/// et 17 pt. Les styles qui fixent leur propre espacement (capitales
/// espacées, chiffres) le gardent.
const double chasseTexte = -0.2;

/// La chasse de la plateforme : SF Pro se resserre, Roboto est dessinée pour
/// se lire sans retouche — sur Android, seul l'espacement ajouté par
/// Material 3 disparaît.
double _chasse(double ios) =>
    defaultTargetPlatform == TargetPlatform.iOS ? ios : 0;

/// Une typographie Material 3 dont seule la géométrie change : chasse d'iOS,
/// interligne naturel de la police. Couleurs et familles de polices restent
/// celles de Material pour la plateforme — la police du système.
Typography typographie(ColorScheme schema) {
  TextStyle iOS(TextStyle? m, {double chasse = chasseTexte}) => TextStyle(
        debugLabel: '${m!.debugLabel} pronowin',
        inherit: false,
        fontSize: m.fontSize,
        fontWeight: m.fontWeight,
        letterSpacing: _chasse(chasse),
        textBaseline: m.textBaseline,
        leadingDistribution: m.leadingDistribution,
      );
  const g = Typography.englishLike2021;
  final geometrie = TextTheme(
    displayLarge:   iOS(g.displayLarge, chasse: 0),
    displayMedium:  iOS(g.displayMedium, chasse: 0),
    displaySmall:   iOS(g.displaySmall, chasse: 0),
    headlineLarge:  iOS(g.headlineLarge, chasse: 0),
    headlineMedium: iOS(g.headlineMedium, chasse: 0),
    headlineSmall:  iOS(g.headlineSmall, chasse: 0),
    titleLarge:     iOS(g.titleLarge, chasse: -0.3),
    titleMedium:    iOS(g.titleMedium),
    titleSmall:     iOS(g.titleSmall),
    bodyLarge:      iOS(g.bodyLarge),
    bodyMedium:     iOS(g.bodyMedium),
    bodySmall:      iOS(g.bodySmall, chasse: -0.1),
    labelLarge:     iOS(g.labelLarge),
    labelMedium:    iOS(g.labelMedium, chasse: -0.1),
    labelSmall:     iOS(g.labelSmall, chasse: 0),
  );
  return Typography.material2021(
    platform: defaultTargetPlatform,
    colorScheme: schema,
    englishLike: geometrie,
  );
}
