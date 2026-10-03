import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ce que l'écran promet de la bankroll, et comment il la nomme.
///
/// ── Un mot de trop ────────────────────────────────────────────────────────
///
/// L'état vide annonçait que PronoWin « calcule automatiquement les mises
/// **optimales** ». La suggestion vaut une part fixe du solde selon la note de
/// l'analyste — 1,5 %, 3 % ou 5 % — sans probabilité ni cote. Il n'y a aucune
/// optimisation, donc rien qui justifie ce mot.
///
/// C'est le même excès que le « Kelly simplifié » déjà retiré du service, sur
/// l'écran qui présente la fonction pour la première fois. La liste des
/// arguments, juste en dessous, le disait pourtant correctement : « Mises
/// calculées selon ton solde et la confiance ».
///
/// ── Un mot jamais expliqué ────────────────────────────────────────────────
///
/// Le même paragraphe employait « bankroll » trois fois, dont « la discipline
/// bankroll », sans jamais dire ce que c'était : il expliquait la fonction
/// avec le terme que la fonction doit justement apprendre.
///
/// ── Et un genre flottant ──────────────────────────────────────────────────
///
/// « Configure ton bankroll » ici, « Mon Bankroll » sur l'accueil, « ton
/// bankroll » dans deux boîtes de mise. Le mot est féminin dans l'usage ; en
/// changer d'un écran à l'autre donne l'impression de deux applications.
void main() {
  late String vide;

  /// Le code seul. Les commentaires citent « optimales » et « discipline
  /// bankroll » à dessein — expliquer ce qui a été retiré demande de l'écrire,
  /// et un contrôle qui se valide sur sa propre prose ne contrôle rien.
  String codeSeul(String source) => source
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  setUpAll(() {
    vide = codeSeul(
        File('lib/features/bankroll/presentation/pages/bankroll_page.dart')
            .readAsStringSync());
  });

  group('aucune précision qui ne soit calculée', () {
    test('plus de mises « optimales »', () {
      expect(vide, isNot(contains('optimales')),
          reason: 'la suggestion est une part fixe du solde : promettre une '
              'optimisation annonce un calcul qui n\'existe pas');
    });

    test('la nature du calcul est dite, pas son résultat', () {
      // Sans les pourcentages : ils vivent côté serveur, et les recopier ici
      // en ferait une seconde source qui prendrait du retard.
      expect(vide, contains('confiance de'),
          reason: 'ce qui fait varier la mise doit être dit');
      expect(vide, isNot(contains('1,5 %')),
          reason: 'les pourcentages appartiennent au serveur');
    });
  });

  group('le terme est expliqué là où il apparaît', () {
    test('l\'état vide dit ce qu\'est une bankroll', () {
      expect(vide, contains("l'argent que tu réserves aux paris"),
          reason: 'expliquer la fonction avec le mot à apprendre '
              'n\'apprend rien');
    });

    test('et ne parle plus de « discipline bankroll »', () {
      expect(vide, isNot(contains('discipline bankroll')));
    });
  });

  group('le mot garde le même genre partout', () {
    test('aucun écran ne le met au masculin', () {
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final code = f.readAsStringSync();
        for (final tournure in ['ton bankroll', 'mon bankroll', 'Mon Bankroll',
                                'le bankroll', 'Ton Bankroll']) {
          if (code.contains(tournure)) {
            fautifs.add('${f.path.replaceAll(r'\', '/')} : $tournure');
          }
        }
      }
      expect(fautifs, isEmpty,
          reason: 'le genre change d\'un écran à l\'autre :\n'
              '${fautifs.join('\n')}');
    });
  });
}
