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
void main() {
  const chemin =
      'lib/features/accueil/presentation/pages/accueil/entete.dart';
  final source = File(chemin).readAsStringSync();

  /// Le code seul, commentaires exclus — ils citent les phrases fautives.
  String codeSeul() => source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('le titre commercial existe toujours', () {
    // Sans ancre, les contrôles suivants verdiraient sur un fichier remanié.
    expect(source, contains('de réussite'));
    expect(source, contains('headline'));
  });

  test('le titre exige un échantillon suffisant', () {
    final code = codeSeul();
    final i = code.indexOf('% de réussite');
    expect(i, greaterThan(-1), reason: 'titre introuvable');

    // La condition qui gouverne ce titre doit peser le nombre de pronostics
    // tranchés, pas seulement le taux.
    final avant = code.substring(0, i);
    final condition = avant.lastIndexOf('if (');
    expect(condition, greaterThan(-1));

    final garde = avant.substring(condition);
    expect(garde.contains('tranches'), isTrue,
      reason: 'le titre s\'affiche sans regarder la taille de l\'échantillon : '
              'un seul pronostic gagné suffirait à promettre 100 %');
  });

  test('le seuil commercial est celui du dépôt', () {
    expect(codeSeul(), contains('echantillonCommercial = 10'),
      reason: 'le backend documente ECHANTILLON_MINIMAL = 10 pour le bilan '
              'Premium : deux seuils différents pour la même promesse '
              'finiraient par diverger');
  });

  test('le titre n\'invente pas de période', () {
    // `getPublicStats()` ne filtre pas par date : annoncer « cette semaine »
    // décrivait un découpage inexistant.
    final i = codeSeul().indexOf('% de réussite');
    final phrase = codeSeul().substring(i, i + 120);
    expect(phrase.contains('cette semaine'), isFalse,
      reason: 'le chiffre porte sur tous les pronostics publiés, pas sur une '
              'semaine');
  });
}
