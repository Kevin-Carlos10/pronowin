import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Les textes informatifs se lisent, dans les deux thèmes.
///
/// ── Ce qui était affiché ──────────────────────────────────────────────────
///
/// `textM` valait `#4A5568` en sombre et `#A0AEC0` en clair. Sur les fonds de
/// l'application, cela donne **2,27:1** et **2,26:1** — la moitié du minimum.
///
/// Ces gris ne servent pas qu'à décorer : ils portent les libellés, les dates,
/// les légendes et les onglets. Un contraste de 2,3 les rend illisibles au
/// soleil, sur un écran bon marché, ou pour quiconque a une vue moyenne.
///
/// ── Ce que ce banc mesure, et ce qu'il ne mesure pas ──────────────────────
///
/// Il **recalcule** les rapports à partir des valeurs écrites dans
/// `app_theme.dart`, selon la formule WCAG 2.2. Un contrôle textuel se serait
/// contenté de vérifier que la couleur a changé ; celui-ci vérifie qu'elle
/// suffit, et il tombera si quelqu'un la repousse trop bas demain.
///
/// Il ne certifie pas l'accessibilité de l'application : il porte sur ces
/// couleurs-ci, sur ces fonds-là. Les couleurs posées en dur dans un écran
/// particulier lui échappent.
///
/// Référence : https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
void main() {
  /// Seuil WCAG AA pour le texte courant.
  const seuilTexteCourant = 4.5;

  /// Seuil WCAG AA pour les composants non textuels (icônes, bordures utiles).
  const seuilComposant = 3.0;

  double canalLineaire(int v) {
    final c = v / 255.0;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  double luminance(int couleur) {
    final r = (couleur >> 16) & 0xFF;
    final v = (couleur >> 8) & 0xFF;
    final b = couleur & 0xFF;
    return 0.2126 * canalLineaire(r) + 0.7152 * canalLineaire(v) + 0.0722 * canalLineaire(b);
  }

  double contraste(int a, int b) {
    final la = luminance(a), lb = luminance(b);
    final clair = math.max(la, lb), sombre = math.min(la, lb);
    return (clair + 0.05) / (sombre + 0.05);
  }

  late String theme;

  setUpAll(() {
    final f = File('lib/core/theme/app_theme.dart');
    if (!f.existsSync()) fail('Thème introuvable : ${f.path}');
    theme = f.readAsStringSync();
  });

  /// Lit les deux couleurs d'un accesseur `Color get nom => isDark ? A : B;`.
  ///
  /// Les valeurs sont prises **dans le fichier**, jamais recopiées ici : un
  /// banc qui porte sa propre copie de la palette ne mesure que lui-même.
  ({int sombre, int clair}) couleurs(String nom) {
    // `surface` s'écrit `Colors.white` côté clair : le lecteur accepte les
    // deux formes plutôt que d'exiger une réécriture du thème pour le banc.
    const valeur = r'(?:const Color\(0x(?:FF)?[0-9A-Fa-f]{6}\)|Colors\.white|Colors\.black)';
    final m = RegExp('Color get $nom\\s*=>\\s*isDark\\s*\\?\\s*($valeur)'
                     '\\s*:\\s*($valeur)')
        .firstMatch(theme);
    if (m == null) fail('Accesseur « $nom » introuvable ou de forme inattendue');

    int lire(String brut) {
      if (brut.contains('Colors.white')) return 0xFFFFFFFF;
      if (brut.contains('Colors.black')) return 0xFF000000;
      final hexa = RegExp(r'0x(?:FF)?([0-9A-Fa-f]{6})').firstMatch(brut)!.group(1)!;
      return 0xFF000000 | int.parse(hexa, radix: 16);
    }

    return (sombre: lire(m.group(1)!), clair: lire(m.group(2)!));
  }

  group('les textes atteignent le seuil de lecture', () {
    // Les trois fonds sur lesquels un texte peut se poser.
    const fondsNoms = ['bg', 'surface', 'surfaceD'];

    for (final nomTexte in ['textP', 'textS', 'textM']) {
      test('$nomTexte, sur les trois fonds et les deux thèmes', () {
        final t = couleurs(nomTexte);

        for (final nomFond in fondsNoms) {
          final f = couleurs(nomFond);

          final rSombre = contraste(t.sombre, f.sombre);
          expect(rSombre, greaterThanOrEqualTo(seuilTexteCourant),
              reason: 'sombre : $nomTexte sur $nomFond '
                      '= ${rSombre.toStringAsFixed(2)}:1');

          final rClair = contraste(t.clair, f.clair);
          expect(rClair, greaterThanOrEqualTo(seuilTexteCourant),
              reason: 'clair : $nomTexte sur $nomFond '
                      '= ${rClair.toStringAsFixed(2)}:1');
        }
      });
    }
  });

  group('la hiérarchie reste lisible', () {
    test('trois niveaux distincts, pas trois nuances du même gris', () {
      // Contrepartie : tout remonter à 15:1 passerait le contrôle ci-dessus en
      // effaçant la différence entre principal, secondaire et discret. Une
      // hiérarchie qui ne se voit plus ne sert plus à rien.
      final p = couleurs('textP');
      final s = couleurs('textS');
      final m = couleurs('textM');
      final fond = couleurs('surface');

      for (final theme in ['sombre', 'clair']) {
        final ct = theme == 'sombre'
            ? [p.sombre, s.sombre, m.sombre, fond.sombre]
            : [p.clair, s.clair, m.clair, fond.clair];

        final rp = contraste(ct[0], ct[3]);
        final rs = contraste(ct[1], ct[3]);
        final rm = contraste(ct[2], ct[3]);

        expect(rp, greaterThan(rs), reason: '$theme : principal ≤ secondaire');
        expect(rs, greaterThan(rm), reason: '$theme : secondaire ≤ discret');
        expect(rs - rm, greaterThan(0.5),
            reason: '$theme : secondaire et discret se confondent '
                    '(${rs.toStringAsFixed(2)} contre ${rm.toStringAsFixed(2)})');
      }
    });
  });

  group("l'icône de section reste distinguable", () {
    test('au moins le seuil des composants non textuels', () {
      // Une icône n'est pas du texte : WCAG demande 3:1, pas 4,5.
      final i = couleurs('sectionIcon');
      final fond = couleurs('surface');

      expect(contraste(i.sombre, fond.sombre),
          greaterThanOrEqualTo(seuilComposant));
      expect(contraste(i.clair, fond.clair),
          greaterThanOrEqualTo(seuilComposant));
    });
  });

  group('le banc mesure vraiment', () {
    test('la formule reconnaît un contraste insuffisant', () {
      // Sans ce point, une erreur de calcul rendrait tous les contrôles
      // ci-dessus verts sans rien vérifier. Les valeurs sont celles que
      // l'audit a relevées.
      expect(contraste(0xFF4A5568, 0xFF151B2E), lessThan(2.5));
      expect(contraste(0xFFA0AEC0, 0xFFFFFFFF), lessThan(2.5));
      // Et un contraste maximal doit rendre 21.
      expect(contraste(0xFF000000, 0xFFFFFFFF), closeTo(21.0, 0.01));
    });
  });
}
