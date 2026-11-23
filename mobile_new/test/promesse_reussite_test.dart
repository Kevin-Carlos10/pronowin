import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un taux de réussite montré à un prospect doit reposer sur un échantillon.
///
/// La carte Premium de l'accueil annonçait « 90 % de réussite cette semaine »
/// dès que `winRate` dépassait 70, sans jamais regarder le nombre de
/// pronostics tranchés. Deux défauts s'y superposaient :
///
///   - **aucun seuil.** Le même fichier en applique un vingt lignes plus haut
///     (`totalFinished >= 3` sur la bande de statistiques), et le backend fixe
///     `ECHANTILLON_MINIMAL = 10` pour le bilan Premium, avec cette phrase :
///     « l'appelant doit alors se taire plutôt que d'annoncer 100 % ou 0 % ».
///     Ce titre est cet appelant — l'argument commercial montré aux prospects
///     — et c'était le seul endroit à ne pas suivre la règle ;
///
///   - **une sélection favorable.** La condition ne se déclenchant qu'au-dessus
///     de 70, un petit échantillon flatteur devenait une promesse tandis qu'un
///     petit échantillon défavorable disparaissait sans bruit.
///
/// S'y ajoutait une période inventée : `getPublicStats()` compte *tous* les
/// pronostics publiés ayant un résultat, sans filtre de date. « Cette semaine »
/// décrivait un découpage qui n'existe pas.
///
/// ── Depuis le 23 novembre 2026 : plus de taux pour un prospect ────────────
///
/// Le taux de réussite est réservé aux abonnés Premium (décision de
/// l'utilisateur). Le titre de la carte Premium, qui s'adresse par définition
/// aux non-abonnés, ne le cite donc plus du tout — la question de son
/// échantillon disparaît avec lui. Et la tuile « Réussite » de l'accueil ne
/// s'affiche qu'à un abonné. Le serveur ne l'envoie d'ailleurs plus aux
/// autres (`taux_reserve.ts`).
void main() {
  const chemin =
      'lib/features/accueil/presentation/pages/accueil/entete.dart';
  final source = File(chemin).readAsStringSync();

  /// Le code seul, commentaires exclus — ils citent les phrases retirées.
  String codeSeul() => source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('la carte Premium existe toujours, avec son titre', () {
    // Sans ancre, le contrôle suivant verdirait sur un fichier remanié.
    expect(source, contains('class _PremiumBanner'));
    expect(source, contains('headline'));
  });

  test('le titre commercial ne cite plus de taux de réussite', () {
    expect(codeSeul(), isNot(contains('% de réussite')),
      reason: 'le taux est réservé aux abonnés Premium : la carte qui '
              "s'adresse aux non-abonnés ne peut pas l'annoncer");
    // La carte elle-même ne lit plus le taux.
    final code = codeSeul();
    final debut = code.indexOf('class _PremiumBanner');
    final fin = code.indexOf('\nclass ', debut + 1);
    final carte = code.substring(debut, fin < 0 ? code.length : fin);
    expect(carte, isNot(contains('winRate')));
  });

  test("la tuile « Réussite » ne s'affiche qu'à un abonné", () {
    final code = codeSeul();
    final tuile = code.indexOf('tr(context, "Réussite")');
    expect(tuile, greaterThan(-1), reason: 'tuile introuvable');
    final garde = code.lastIndexOf('if (avecTaux)', tuile);
    expect(garde, greaterThan(-1),
      reason: 'la tuile Réussite doit dépendre de avecTaux');
    expect(code, contains('final avecTaux = isPremium && winRate != null;'));
  });
}
