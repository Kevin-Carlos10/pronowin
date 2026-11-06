import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/code_ussd.dart';

/// Le code composé doit désigner le bon numéro et le bon montant.
///
/// C'est un écran où une erreur envoie l'argent de quelqu'un ailleurs, et où
/// rien ne la signale : le code composerait, l'opérateur l'accepterait, le
/// virement réussirait — simplement pas au bon endroit. Il n'y a ni exception
/// à attraper, ni journal à relire.
///
/// D'où deux exigences tenues ici :
///
///  - le numéro vient du numéro de réception publié, jamais du modèle ;
///  - à la moindre ambiguïté, aucun code n'est proposé. L'écran affiche alors
///    le numéro seul, comme il le faisait avant cette fonctionnalité.
void main() {
  group('le numéro d\'abonné', () {
    test('ce sont les huit derniers chiffres', () {
      expect(numeroAbonne('22645568158'), '45568158');
    });

    test('un numéro déjà national est rendu tel quel', () {
      expect(numeroAbonne('45568158'), '45568158');
    });

    test('la mise en forme de saisie est ignorée', () {
      expect(numeroAbonne('+226 45 56 81 58'), '45568158');
      expect(numeroAbonne('226-45.56.81.58'), '45568158');
    });

    test('un numéro trop court n\'est pas complété', () {
      // Mieux vaut rendre ce qu'on a et laisser l'appelant refuser, que
      // fabriquer des chiffres.
      expect(numeroAbonne('4556'), '4556');
      expect(numeroAbonne('sans chiffre'), '');
    });
  });

  group('le code composé', () {
    test('Orange Money, formule mensuelle', () {
      expect(
        construireCodeUssd(
          modele: '*144*10*{numero}*{montant}#',
          numero: '22645568158',
          montant: 6000),
        '*144*10*45568158*6000#');
    });

    test('Orange Money, formule annuelle', () {
      expect(
        construireCodeUssd(
          modele: '*144*10*{numero}*{montant}#',
          numero: '22645568158',
          montant: 54000),
        '*144*10*45568158*54000#');
    });

    test('le montant est composable, donc sans séparateur', () {
      // L'écran écrit « 54 000 FCFA » à côté ; le code, lui, est composé.
      final code = construireCodeUssd(
        modele: '*144*{montant}#', numero: '22645568158', montant: 54000);
      expect(code, '*144*54000#');
      expect(code, isNot(contains(' ')));
    });

    test('un modèle sans montant reste valable', () {
      expect(
        construireCodeUssd(
          modele: '*555*{numero}#', numero: '22645568158', montant: 6000),
        '*555*45568158#');
    });

    test('le numéro vient du numéro publié, pas du modèle', () {
      // La garantie centrale : changer le numéro de réception change le code,
      // sans que personne n'ait à modifier le modèle.
      expect(
        construireCodeUssd(
          modele: '*144*10*{numero}*{montant}#',
          numero: '22670123456',
          montant: 6000),
        '*144*10*70123456*6000#');
    });
  });

  group('quand aucun code ne peut être proposé', () {
    test('aucun modèle configuré', () {
      for (final vide in [null, '', '   ']) {
        expect(
          construireCodeUssd(modele: vide, numero: '22645568158', montant: 6000),
          isNull);
      }
    });

    test('numéro inexploitable', () {
      expect(
        construireCodeUssd(
          modele: '*144*{numero}#', numero: '', montant: 6000),
        isNull);
    });

    test('un marqueur inconnu ne s\'affiche jamais tel quel', () {
      // Un modèle saisi par une version plus ancienne de l'API pourrait en
      // contenir un. « *144*{somme}# » composé tel quel échouerait chez
      // l'opérateur, et c'est l'application qu'on jugerait.
      expect(
        construireCodeUssd(
          modele: '*144*{numero}*{somme}#', numero: '22645568158', montant: 6000),
        isNull);
    });
  });
}
