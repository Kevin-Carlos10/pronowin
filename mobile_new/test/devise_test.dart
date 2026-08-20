import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/devise.dart';

/// L'écran de confirmation de mise affichait « 1 500 XOF ». XOF est un code
/// bancaire ; ce qui est écrit sur les billets, et ce que les gens disent, c'est
/// « FCFA » — que le reste de l'app emploie à vingt-sept endroits. Le code ISO
/// reste la donnée stockée ; il ne doit simplement jamais être lu par un
/// utilisateur.
void main() {
  group('nomDevise — le code ISO ne s\'affiche pas', () {
    test('les deux francs CFA se disent FCFA', () {
      expect(nomDevise('XOF'), 'FCFA');
      expect(nomDevise('XAF'), 'FCFA');
    });

    test('l\'euro prend son symbole', () {
      expect(nomDevise('EUR'), '€');
    });

    test('le franc guinéen n\'a pas d\'autre nom d\'usage', () {
      expect(nomDevise('GNF'), 'GNF');
    });

    test('la casse est indifférente', () {
      expect(nomDevise('xof'), 'FCFA');
    });

    test('un code inconnu est rendu tel quel plutôt que perdu', () {
      // Une devise ajoutée côté serveur sans mise à jour de l'app doit rester
      // lisible : un sigle vaut mieux qu'un montant sans unité.
      expect(nomDevise('USD'), 'USD');
    });

    test('null ou vide ne produit pas « null »', () {
      expect(nomDevise(null), '');
      expect(nomDevise(''), '');
    });
  });

  group('libelleChoixDevise — le sélecteur doit lever l\'ambiguïté', () {
    test('les deux FCFA sont distingués par leur zone', () {
      // Dans le sélecteur, et là seulement, « FCFA » seul serait ambigu :
      // deux entrées porteraient le même nom.
      final ouest = libelleChoixDevise('XOF');
      final centre = libelleChoixDevise('XAF');

      expect(ouest, isNot(equals(centre)));
      expect(ouest, contains('FCFA'));
      expect(centre, contains('FCFA'));
      expect(ouest, contains('Ouest'));
      expect(centre, contains('centrale'));
    });

    test('une devise sans homonyme reste courte', () {
      expect(libelleChoixDevise('EUR'), '€');
    });
  });
}
