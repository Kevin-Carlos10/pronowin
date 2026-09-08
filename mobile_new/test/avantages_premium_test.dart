import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La page qui demande 15 $ par mois ne doit rien promettre qu'elle ne livre.
///
/// Deux défauts constatés sur cet écran, le même jour :
///
///   - « Tous les tutoriels — Bibliothèque complète débloquée » y figurait
///     avec un cadenas, alors que les quatre tutoriels sont en accès libre.
///     L'abonné payait pour ce qu'il avait déjà, à l'endroit exact de
///     l'achat ;
///
///   - la pastille « 5 avantages » était écrite en dur, à cent cinquante
///     lignes de la liste qu'elle compte. Retirer un avantage laissait donc
///     l'écran se contredire sous les yeux du lecteur.
///
/// Le second est le plus instructif : ce n'est pas une phrase fausse, c'est
/// une valeur tenue à deux endroits. Elle finit toujours par diverger, et le
/// jour où elle diverge, c'est sur un écran de paiement.
///
/// `_AbonnementTab` et sa liste sont privés : un test de rendu devrait monter
/// la page entière et ses providers. Le dépôt garde déjà ses surfaces privées
/// par le texte source (`canal_store_test.dart`) ; ce contrôle suit la même
/// règle, et `tool/injections_avantages.py` vérifie qu'il mord.
void main() {
  final source = File(
    'lib/features/compte/presentation/pages/compte_page.dart',
  ).readAsStringSync();

  /// Les seules lignes d'avantage, commentaires exclus.
  ///
  /// Le premier jet analysait tout le bloc `_features`, commentaires compris.
  /// Une apostrophe française — « qu'un examinateur » — y ouvrait une fausse
  /// chaîne qui courait sur plusieurs lignes, et le contrôle accusait le
  /// commentaire qui explique le correctif. Un test qui se déclenche sur sa
  /// propre justification n'apprend rien à personne.
  List<String> entrees() {
    final debut = source.indexOf('static const _features');
    final fin   = source.indexOf('];', debut);
    return source
        .substring(debut, fin)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('(Icons.'))
        .toList();
  }

  test('la liste des avantages existe toujours', () {
    // Sans cette ancre, les contrôles suivants pourraient verdir en
    // n'inspectant plus rien.
    expect(source, contains('static const _features'));
    expect(source, contains("'Pronostics VIP illimités'"));
  });

  test('le nombre affiché est calculé depuis la liste', () {
    expect(source, contains(r"'${features.length} avantages'"),
      reason: 'la pastille est écrite en dur : elle annoncera un nombre '
              "d'avantages différent de ce que l'écran affiche dès que la "
              'liste changera');

    // Et aucun nombre littéral ne doit subsister devant « avantages ».
    expect(RegExp(r"'\d+ avantages'").hasMatch(source), isFalse,
      reason: 'un compte littéral subsiste');
  });

  test('aucun avantage ne promet un délai chiffré', () {
    // « Réponse sous 2h ouvrées » figurait ici. Un délai chiffré sur une page
    // de paiement n'est pas un argument mais un engagement : il se mesure et
    // se réclame, y compris un dimanche. Les avantages peuvent promettre une
    // priorité, un accès, une quantité — pas une horloge.
    final liste = entrees().join('\n');
    final delai = RegExp(
      r"'[^']*\b\d+\s*(h|heures?|min|minutes?|jours?)\b[^']*'",
      caseSensitive: false,
    ).firstMatch(liste);
    expect(delai?.group(0), isNull,
      reason: 'un avantage annonce un délai : ${delai?.group(0)}');
  });

  test('aucun avantage ne vend les tutoriels', () {
    // Règle du moment, pas règle éternelle : les tutoriels sont des vidéos
    // YouTube tierces, toutes gratuites, et en faire payer l'accès
    // contrevient aux conditions de la plateforme qui les héberge.
    //
    // À REVOIR le jour où PronoWin produira les siennes — ce test devra
    // alors distinguer les vidéos maison des intégrations tierces. Le
    // changer sera un acte délibéré, ce qui est le but.
    final liste = entrees().join('\n');
    expect(liste.contains("'Tous les tutoriels'"), isFalse,
      reason: 'la page de paiement vend un accès aux tutoriels alors '
              "qu'ils sont tous gratuits");
  });
}
