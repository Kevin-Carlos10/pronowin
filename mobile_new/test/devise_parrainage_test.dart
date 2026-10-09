import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Une monnaie, une écriture.
///
/// L'onglet Parrainage affichait la même devise de deux façons, à quatre
/// centimètres d'écart :
///
///     Mes gains parrainage
///     0 FCFA
///     ...
///     500 F   par filleul direct
///     200 F   par filleul indirect
///
/// Aucune erreur, aucun test rouge : deux `Text` écrits à des moments
/// différents, chacun avec le libellé que son auteur avait en tête. C'est la
/// forme la plus courante de ce défaut — personne ne relit deux écrans côte à
/// côte.
///
/// La cause de fond : le serveur publiait les montants sans dire dans quelle
/// devise. L'écran devait donc deviner, et deviner deux fois donne deux
/// réponses. La devise voyage désormais avec les montants.
void main() {
  final compte = File(
    'lib/features/compte/presentation/pages/compte_page.dart',
  );

  /// Le fichier sans ses commentaires : ils citent le défaut, ils ne le portent pas.
  final code = compte
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  group('onglet Parrainage — une seule écriture de la devise', () {
    test('la devise vient du serveur', () {
      // Écrite en dur, elle redeviendrait fausse le jour où les commissions
      // seraient versées autrement.
      expect(code, contains("stats['currency']"));
      expect(code, contains('nomDevise('));
    });

    test('plus aucun libellé de devise écrit à la main', () {
      // Les deux formes trouvées sur la capture d'écran.
      for (final motif in [r'\$comL1 F\b', r'\$comL2 F\b', r'\$v FCFA']) {
        expect(RegExp(motif).hasMatch(code), isFalse, reason: motif);
      }
    });

    test('tous les montants de commission portent la même variable', () {
      // Trois emplacements affichent une commission : les deux tuiles du
      // barème et le compteur des filleuls indirects. Ils étaient six — les
      // étapes et l'encart « Aucun filleul » répétaient le barème (vidéo du
      // 5 octobre 2026). Si l'un gardait son propre libellé, l'incohérence
      // reviendrait exactement là où elle était.
      final avecDevise =
          RegExp(r'\$comL[12] \$devise').allMatches(code).length +
          // Les phrases traduites reçoivent montant ET devise en paramètres.
          RegExp(r'\bcomL[12],\s*devise\b').allMatches(code).length;
      // Toute commission affichée, sans exception : interpolée ou passée en
      // paramètre, hors de sa déclaration.
      final affichees =
          RegExp(r'\$comL[12]\b').allMatches(code).length +
          RegExp(r'\bcomL[12],').allMatches(code).length;

      expect(avecDevise, greaterThanOrEqualTo(3));
      expect(avecDevise, affichees, reason: 'une commission s\'affiche sans la devise');
    });

    test('le solde et les commissions emploient la même source', () {
      // C'est la comparaison qui manquait : le solde disait « FCFA », les
      // commissions « F ». Les deux passent maintenant par `devise`.
      expect(code, contains(r'$v $devise'));
      expect(RegExp(r'final devise = nomDevise\(').hasMatch(code), isTrue);
    });
  });
}
