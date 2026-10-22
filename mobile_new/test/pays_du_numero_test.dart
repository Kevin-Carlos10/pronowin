import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/widgets/country_pill_selector.dart';

/// Le pays proposé pour « le numéro depuis lequel vous avez envoyé l'argent ».
///
/// ── Ce qui était proposé ──────────────────────────────────────────────────
///
/// La locale de l'appareil. Sur un téléphone réglé en anglais américain, le
/// champ affichait donc **+1** — juste au-dessus d'un exemple « 70 00 00 00 »
/// qui est burkinabè. L'écran se contredisait à deux lignes d'intervalle.
///
/// Ce n'est pas un détail d'affichage. Ce numéro sert à rapprocher un virement
/// reçu d'un abonné qui le réclame. Déclaré sous le mauvais indicatif, le
/// versement existe mais n'appartient plus à personne, et il faut le refuser à
/// quelqu'un qui a réellement payé.
///
/// ── Ce qui est proposé maintenant ─────────────────────────────────────────
///
/// Le pays du numéro **qui reçoit**. L'expéditeur est chez le même opérateur,
/// par construction : c'est ce qui rend le transfert possible. Et rien n'est
/// écrit en dur — ajouter un numéro sénégalais déplacera le défaut sans que
/// personne n'y touche.
void main() {
  group('le pays se déduit du numéro de réception', () {
    test('le numéro Orange Money en service désigne le Burkina', () {
      expect(paysDuNumero('22645568158')?.countryCode, 'BF');
    });

    test('la mise en forme ne change rien', () {
      expect(paysDuNumero('+226 45 56 81 58')?.countryCode, 'BF');
    });

    test('un autre indicatif donne un autre pays', () {
      // La garantie qui compte : rien n'est figé sur le Burkina.
      expect(paysDuNumero('221771234567')?.countryCode, 'SN');
      expect(paysDuNumero('2250712345678')?.countryCode, 'CI');
    });
  });

  group('quand le numéro ne dit rien', () {
    test('un numéro sans indicatif ne fait rien deviner', () {
      // Huit chiffres, c'est le numéro national seul : il ne porte aucun pays.
      // Inventer le Burkina ici serait recréer la valeur en dur qu'on retire.
      expect(paysDuNumero('45568158'), isNull);
    });

    test('vide ou absent aussi', () {
      expect(paysDuNumero(null), isNull);
      expect(paysDuNumero(''), isNull);
      expect(paysDuNumero('   '), isNull);
    });

    test('un indicatif inconnu ne rend pas un pays au hasard', () {
      expect(paysDuNumero('99912345678'), isNull);
    });
  });

  group('la locale reste le dernier recours', () {
    test('elle répond toujours, et jamais null', () {
      // C'est ce qui permet à l'écran de composer
      // `paysDuNumero(...) ?? deviceDefaultCountry()` sans cas vide.
      expect(deviceDefaultCountry().countryCode, isNotEmpty);
    });
  });
}
