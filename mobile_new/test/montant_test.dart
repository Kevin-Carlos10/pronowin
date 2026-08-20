import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/shared/utils/montant.dart';

/// Trois formateurs de montants cohabitaient, chacun privé à son écran, et
/// celui de la page « Détail du pari » abrégeait. Un gain de 2 025 F s'y lisait
/// « 2.0 k ». Aucune erreur, aucun test rouge : juste 25 F qui disparaissent
/// sur l'écran qu'on ouvre pour vérifier ses chiffres.
void main() {
  /// Espace fine insécable (U+202F). Écrite en échappement plutôt qu'au
  /// clavier : un caractère invisible dans une chaîne attendue rend l'échec
  /// illisible — « 2 025 » contre « 2 025 », visuellement identiques.
  const fine = ' ';

  group('montantExact — la page détail ne doit rien arrondir', () {
    test('le cas signalé : 2 025 reste 2 025', () {
      // 1 500 × 1,35 — le gain potentiel de la capture.
      expect(montantExact(2025), '2${fine}025');
      expect(montantExact(2025), isNot(contains('k')));
    });

    test('les milliers sont groupés', () {
      expect(montantExact(1500), '1${fine}500');
      expect(montantExact(12345), '12${fine}345');
      expect(montantExact(1234567), '1${fine}234${fine}567');
    });

    test('sous mille, aucun séparateur', () {
      expect(montantExact(999), '999');
      expect(montantExact(0), '0');
    });

    test('le séparateur est une espace fine insécable', () {
      // Une espace ordinaire couperait « 2 025 » en fin de ligne.
      expect(montantExact(2025).codeUnits, contains(0x202F));
      expect(montantExact(2025).codeUnits, isNot(contains(0x0020)));
    });

    test('les négatifs gardent leur signe', () {
      expect(montantExact(-1500), '-1${fine}500');
    });

    test('les décimales sont arrondies, jamais tronquées', () {
      // Le serveur renvoie 2025.0000000000002 (flottant) : l'affichage ne doit
      // ni montrer ce bruit ni perdre l'unité.
      expect(montantExact(2025.0000000000002), '2${fine}025');
      expect(montantExact(1499.6), '1${fine}500');
    });
  });

  group('montantSigne — le + ne s\'écrit que sur un gain', () {
    test('un gain porte le signe', () => expect(montantSigne(525), '+525'));
    test('une perte porte le sien',  () => expect(montantSigne(-525), '-525'));
    test('zéro n\'en porte aucun',   () => expect(montantSigne(0), '0'));
  });

  group('montantCourt — l\'abrégé reste possible, mais explicite', () {
    test('abrège au-delà du millier', () {
      expect(montantCourt(12345), '12.3 k');
      expect(montantCourt(2000), '2 k');
    });

    test('reste exact en dessous', () {
      expect(montantCourt(999), '999');
    });

    test('son nom dit ce qu\'il fait', () {
      // Garde-fou de lisibilité : un appelant qui écrit `montantCourt` sait
      // qu'il perd des unités. C'est le nom qui empêche l'usage par mégarde,
      // pas un commentaire.
      expect(montantCourt(2025), isNot(montantExact(2025)));
    });
  });

  group('confiance — une seule échelle dans toute l\'app', () {
    test('le score 3 vaut 80 %, pas 60 %', () {
      // La page « Détail du pari » affichait « 3/5 ». Lu comme une fraction,
      // c'est 60 % — vingt points sous ce que la page du match annonce pour la
      // même donnée.
      expect(MatchEntity.percentForConfidence(3), 80);
      expect(MatchEntity.percentForConfidence(3), isNot(60));
    });

    test('la table couvre les cinq paliers', () {
      expect([1, 2, 3, 4, 5].map(MatchEntity.percentForConfidence).toList(),
          [60, 70, 80, 90, 95]);
    });

    test('un score hors bornes est ramené dans l\'échelle', () {
      expect(MatchEntity.percentForConfidence(0), 60);
      expect(MatchEntity.percentForConfidence(9), 95);
    });
  });

  group('retour total et bénéfice ne se confondent pas', () {
    test('sur le pari de la capture', () {
      const mise = 1500.0, cote = 1.35;
      final retour = mise * cote;
      final benefice = retour - mise;

      // L'écran affichait « Gain potentiel +2 025 » : le « + » faisait lire un
      // bénéfice là où il y avait un retour, mise comprise.
      expect(montantExact(retour), '2${fine}025');
      expect(montantSigne(benefice), '+525');
      expect(retour - benefice, mise,
          reason: 'l\'écart entre les deux vaut exactement la mise');
    });
  });
}
