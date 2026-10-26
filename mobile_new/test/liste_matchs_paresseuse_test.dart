import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// L'écran le plus visité de l'application construisait tout, tout de suite.
///
/// `ListView(children:)` construit et dispose **chacun** de ses enfants, même
/// ceux qui se trouvent dix écrans plus bas. Les jours chargés, cela faisait
/// soixante cartes de match construites pour six visibles.
///
/// L'animation d'entrée aggravait le compte : chaque liste portait sa propre
/// formule — `palier + ligue×80 + rang×60`, `80 + rang×70`, `rang×60` — toutes
/// croissantes sans limite. Une carte en fin de liste attendait plus d'une
/// seconde et demie avant d'apparaître, hors écran, pour personne.
///
/// Ce même délai interdisait la liste paresseuse : une carte construite au
/// moment où elle entre à l'écran serait restée vide le temps d'un délai déjà
/// écoulé. Les deux devaient donc changer ensemble.
void main() {
  /// Un fichier sans ses commentaires : ils citent le défaut corrigé, et un
  /// contrôle qui se valide sur sa propre prose ne garde rien.
  String codeSeul(String chemin) => File(chemin)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  final page   = codeSeul('lib/features/pronostics/presentation/pages/'
                          'pronostics_page.dart');
  final motion = codeSeul('lib/core/utils/motion.dart');

  group('la liste des matchs est paresseuse', () {
    test('elle se construit à la demande', () {
      expect(page, contains('ListView.builder('));
      expect(page, contains('itemCount:  elements.length'));
      expect(page, contains('itemBuilder:'));
    });

    test('plus aucun ListView glouton sur cet écran', () {
      final gloutons = RegExp(r'ListView\(\s*\n\s*controller:')
          .allMatches(page).length;

      expect(gloutons, 0);
    });
  });

  group('l\'entrée en cascade est bornée, et au même endroit', () {
    test('plus aucune formule croissante dans l\'écran', () {
      // Les trois qui restaient après la première correction — et que seul
      // un contrôle a fait apparaître.
      for (final motif in [
        r'delay:\s*Duration\(milliseconds:\s*delayOffset',
        r'e\.key \* 60',
        r'e\.key \* 70',
        r'80 \+ e\.key',
      ]) {
        expect(RegExp(motif).hasMatch(page), isFalse, reason: motif);
      }
      expect(page.contains('delayOffset'), isFalse);
    });

    test('l\'écran passe par l\'aide partagée', () {
      // Trois listes, trois formules différentes : c'est en les laissant
      // chacune décider que l'incohérence s'installe.
      expect(page, contains('context.entree('));
      expect(RegExp(r'context\.entree\(').allMatches(page).length,
          greaterThanOrEqualTo(4));
    });

    test('la borne couvre un écran sans dépasser', () {
      final m = RegExp(r'elementsAnimes = (\d+)').firstMatch(motion);
      expect(m, isNotNull, reason: 'aucune borne déclarée');

      final borne = int.parse(m!.group(1)!);
      // Assez pour la première hauteur d'écran…
      expect(borne, greaterThanOrEqualTo(4));
      // …sans réintroduire une cascade que personne ne verra démarrer.
      expect(borne, lessThanOrEqualTo(15));

      expect(motion, contains('index >= elementsAnimes'));
    });

    test('le dernier élément animé n\'attend pas', () {
      final borne = int.parse(
          RegExp(r'elementsAnimes = (\d+)').firstMatch(motion)!.group(1)!);
      final pas = int.parse(
          RegExp(r'pasEntreeMs = (\d+)').firstMatch(motion)!.group(1)!);

      // Au-delà d'une demi-seconde, l'écran paraît lent au lieu de vif.
      expect((borne - 1) * pas, lessThanOrEqualTo(500));
    });

    test('le réglage « animations réduites » est respecté', () {
      // Un utilisateur qui a demandé moins de mouvement au système ne doit pas
      // en recevoir davantage parce que l'écran est important.
      expect(motion, contains('animationsReduites'));
      expect(RegExp(r'index >= elementsAnimes \|\| animationsReduites')
          .hasMatch(motion), isTrue);
    });
  });

  group('une notification ne reconstruit pas tout l\'écran', () {
    test('le compteur de non-lues est lu dans un Consumer, pas dans le build', () {
      // Il était lu en tête du `build` de la page. Une notification qui
      // arrivait reconstruisait donc la barre de dates, les filtres, et
      // l'assemblage de la liste — où chaque ligue est retriée à chaque
      // passage. Pour un chiffre dans un rond de seize pixels.
      final debutBuild = page.indexOf('Widget build(BuildContext context) {');
      expect(debutBuild, greaterThan(-1));

      // La portée du build principal s'arrête au premier widget extrait.
      final finBuild = page.indexOf('class _', debutBuild);
      final corps = page.substring(debutBuild, finBuild == -1 ? page.length : finBuild);

      final lignes = corps.split('\n');
      final indexWatch = lignes.indexWhere((l) => l.contains('unreadCountProvider'));
      expect(indexWatch, greaterThan(-1),
        reason: 'la pastille doit toujours lire le compteur, ailleurs');

      // Il doit être précédé d'un `Consumer(` : c'est lui qui borne la
      // reconstruction. Sans ce contrôle, remonter la ligne de deux crans
      // rétablirait le défaut sans que rien ne le signale.
      final avant = lignes.take(indexWatch).join('\n');
      expect(avant, contains('Consumer(builder:'));
    });
  });
}
