import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/verrou_pari.dart';

/// On ne propose pas d'enregistrer une mise sur un match dont l'issue se sait.
///
/// La carte d'accueil masquait le bouton « Miser » sur `status == 'finished'`
/// seulement. Pendant un match **en direct**, avec le score affiché juste à
/// côté, le bouton restait là — et le serveur n'opposait aucun refus.
///
/// La page détail, elle, était déjà correcte : elle n'affiche le bouton que sur
/// `MatchStatus.upcoming`. Une règle appliquée à un endroit, oubliée à l'autre.
///
/// Le pendant serveur est `backend/src/__tests__/pari_apres_resultat.test.ts`.
void main() {
  final dans2h = DateTime.now().add(const Duration(hours: 2));
  final ilYa2h = DateTime.now().subtract(const Duration(hours: 2));

  group('ce qui reste ouvert', () {
    test('un match à venir, non réglé', () {
      // Contrepartie : une règle qui fermerait tout masquerait le bouton
      // partout, et la bankroll deviendrait inatteignable depuis l'accueil.
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'SCHEDULED', dateMatch: dans2h),
        isTrue,
      );
    });

    test('un match à venir sans date connue', () {
      // Une date absente ne doit pas fermer par défaut : ce serait masquer le
      // bouton sur un défaut de données.
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'SCHEDULED', dateMatch: null),
        isTrue,
      );
    });
  });

  group('ce qui est fermé', () {
    test('un match en direct — le cas que l\'écran laissait passer', () {
      expect(
        pariEncoreOuvert(resultat: null, statutMatch: 'live', dateMatch: dans2h),
        isFalse,
      );
    });

    test('un match terminé', () {
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'FINISHED', dateMatch: ilYa2h),
        isFalse,
      );
    });

    test('un pronostic déjà réglé, même avant le coup d\'envoi', () {
      for (final r in ['WIN', 'LOSS', 'PUSH']) {
        expect(
          pariEncoreOuvert(
              resultat: r, statutMatch: 'SCHEDULED', dateMatch: dans2h),
          isFalse,
          reason: 'résultat $r',
        );
      }
    });

    test('un match commencé mais encore marqué « à venir »', () {
      // Le statut vient d'une synchronisation périodique ; l'heure, non.
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'SCHEDULED', dateMatch: ilYa2h),
        isFalse,
      );
    });

    test('un match reporté ou suspendu', () {
      for (final s in ['POSTPONED', 'SUSPENDED']) {
        expect(
          pariEncoreOuvert(
              resultat: null, statutMatch: s, dateMatch: dans2h),
          isFalse,
          reason: s,
        );
      }
    });

    test('ferme exactement à l\'heure du coup d\'envoi', () {
      final t = DateTime.utc(2026, 9, 20, 18);
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'SCHEDULED', dateMatch: t,
            maintenant: t.subtract(const Duration(milliseconds: 1))),
        isTrue,
      );
      expect(
        pariEncoreOuvert(
            resultat: null, statutMatch: 'SCHEDULED', dateMatch: t,
            maintenant: t),
        isFalse,
      );
    });
  });

  /// La règle ne sert à rien si l'écran cesse de l'appeler.
  ///
  /// Un banc qui n'éprouve que la fonction resterait vert pendant que le bouton
  /// réapparaîtrait sur un match en direct. Le contrôle est textuel : ni le
  /// compilateur ni l'analyseur ne voient une condition d'affichage qui change.
  group('la carte d\'accueil applique la règle', () {
    late String carte;

    setUpAll(() {
      final f = File(
          'lib/features/accueil/presentation/pages/accueil/carte_prono.dart');
      if (!f.existsSync()) fail('Carte introuvable : ${f.path}');
      carte = f.readAsStringSync();
    });

    test('elle consulte la règle', () {
      expect(carte, contains('pariEncoreOuvert('));
    });

    test('le bouton « Miser » en dépend', () {
      expect(carte, contains('pariOuvert'));
      expect(
        RegExp(r'if\s*\(!isLocked\s*&&\s*!isFinished\s*&&\s*odds\s*!=\s*null\)')
            .hasMatch(carte),
        isFalse,
        reason: "l'ancienne condition ne regardait que « terminé »",
      );
    });

    test('elle lui passe la date du match', () {
      // Sans la date, le statut décide seul — et il est en retard d'une
      // synchronisation après chaque coup d'envoi.
      expect(carte, contains("prono['match_date']"));
    });
  });

  /// Deux dépôts, une seule règle.
  ///
  /// Le serveur refuse, l'écran n'affiche pas. Si l'un des deux change seul, le
  /// bouton mène à une erreur, ou disparaît alors que la mise serait acceptée.
  /// On compare donc les statuts que chacun considère comme fermés.
  group('accord avec le backend', () {
    late String regleServeur;

    setUpAll(() {
      final f = File('../backend/src/services/verrou_pari.ts');
      if (!f.existsSync()) fail('Règle serveur introuvable : ${f.path}');
      regleServeur = f.readAsStringSync();
    });

    test('les mêmes statuts ferment la saisie des deux côtés', () {
      // Le serveur distingue `postponed` pour donner un message propre ; les
      // deux le refusent, c'est ce qui compte ici.
      for (final statut in ['live', 'finished', 'suspended', 'postponed']) {
        expect(regleServeur, contains("'$statut'"),
            reason: 'le serveur ne connaît plus le statut $statut');
        expect(
          pariEncoreOuvert(
              resultat: null, statutMatch: statut, dateMatch: dans2h),
          isFalse,
          reason: 'le mobile laisse passer $statut',
        );
      }
    });

    test('les deux ferment à l\'heure, pas seulement sur le statut', () {
      expect(regleServeur, contains('dateMatch.getTime() <= maintenant.getTime()'),
          reason: 'le serveur ne regarde plus l\'heure du coup d\'envoi');
    });

    test('les deux laissent passer une date absente', () {
      expect(regleServeur, contains('dateMatch != null'),
          reason: 'sans cette garde le serveur fermerait sur donnée manquante');
    });
  });
}
