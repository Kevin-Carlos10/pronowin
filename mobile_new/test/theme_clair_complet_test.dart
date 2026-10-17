import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';

import 'aides/code_seul.dart';

/// Le thème clair est un thème, pas le sombre repeint.
///
/// ── Ce qui manquait ───────────────────────────────────────────────────────
///
/// `ColorScheme.light(...)` ne fixait que quatre rôles. Les autres prenaient
/// leurs valeurs par défaut : contours noirs, et `surfaceContainer*` égaux à
/// la surface — menus, feuilles et dialogues avaient la couleur exacte des
/// cartes qu'ils recouvrent. En sombre, `outline` valait du blanc pur.
///
/// Et les écrans écrivaient `AppColors.success` comme couleur de texte : une
/// teinte faite pour le fond sombre, illisible sur blanc. Ce banc tient les
/// deux bouts : le jeu de couleurs complet, et les écrans qui passent par lui.
void main() {
  group('tous les rôles du jeu de couleurs sont choisis', () {
    for (final (nom, t) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
      test('$nom : contours ni noirs ni blancs', () {
        final s = t.colorScheme;
        for (final c in [s.outline, s.outlineVariant]) {
          expect(c, isNot(Colors.black), reason: '$nom : contour noir par défaut');
          expect(c, isNot(Colors.white), reason: '$nom : contour blanc par défaut');
        }
      });

      test('$nom : les surfaces superposées se distinguent des cartes', () {
        final s = t.colorScheme;
        expect(s.surfaceContainerHigh, isNot(s.surface),
            reason: '$nom : menus et feuilles avaient la couleur des cartes');
        expect(s.surfaceContainerHighest, isNot(s.surface));
      });
    }

    test('sombre : menus, feuilles et dialogues un cran au-dessus des cartes', () {
      final t = AppTheme.dark;
      final carte = t.cardTheme.color;
      expect(t.popupMenuTheme.color, isNot(carte));
      expect(t.bottomSheetTheme.backgroundColor, isNot(carte));
      expect(t.dialogTheme.backgroundColor, isNot(carte));
    });
  });

  testWidgets('SurfaceSombre donne le thème sombre à son contenu, en clair', (t) async {
    late AppCl dehors, dedans;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (context) {
        dehors = context.cl;
        return SurfaceSombre(builder: (context) {
          dedans = context.cl;
          return const SizedBox();
        });
      }),
    ));
    expect(dehors.isDark, isFalse);
    expect(dedans.isDark, isTrue,
        reason: 'sur une carte bleu nuit, les gris et les couleurs d\'état '
                'doivent être ceux du sombre');
  });

  test('aucun écran n\'écrit de texte avec une teinte fixe', () {
    // Une teinte vive comme couleur de texte : lisible en sombre, illisible
    // en clair. Les accesseurs `context.cl.*` choisissent selon le thème.
    // Les teintes restent permises pour les aplats, icônes et pastilles
    // (`.withValues`), qui ne sont pas du texte.
    final interdite = RegExp(
        r'AppColors\.(success|error|warning|info|primary|primaryLight)\b(?!\.with)');
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('app_theme.dart')) continue;
      // Le logotype garde l'orange de la marque dans les deux thèmes : un
      // logotype est exempté du seuil de contraste (WCAG 1.4.3).
      if (f.path.endsWith('logotype_pronowin.dart')) continue;
      final code = f.readAsStringSync().pipeCodeSeul();
      for (final style in _appels(code, 'TextStyle(')) {
        final couleur = RegExp(r'\bcolor\s*:([^,]*)').firstMatch(style);
        if (couleur != null && interdite.hasMatch(couleur.group(1)!)) {
          fautes.add('${f.path} : ${couleur.group(0)!.trim()}');
        }
      }
    }
    expect(fautes, isEmpty,
        reason: 'employer context.cl.success, .error, .warning, .info, .accent ou .dore');
  });
}

/// Le texte de chaque appel `nom(...)`, parenthèses équilibrées.
Iterable<String> _appels(String code, String nom) sync* {
  var i = code.indexOf(nom);
  while (i >= 0) {
    var prof = 0;
    var j = i + nom.length - 1;
    for (; j < code.length; j++) {
      if (code[j] == '(') prof++;
      if (code[j] == ')' && --prof == 0) break;
    }
    yield code.substring(i, j < code.length ? j + 1 : code.length);
    i = code.indexOf(nom, i + nom.length);
  }
}
