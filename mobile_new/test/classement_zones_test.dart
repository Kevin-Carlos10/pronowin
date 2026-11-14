import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// Le classement affichait sept colonnes, aucun écusson, et aucune zone.
///
/// « 7ᵉ avec 3 points » ne dit rien tant qu'on ignore si cette place mène en
/// Europe ou frôle la descente — et c'est justement ce qui change la nature
/// d'un match. La donnée existait chez le fournisseur (`description`) et
/// n'était pas lue ; le logo, lui, était récupéré depuis toujours et jamais
/// affiché.
void main() {
  group('lecture de la réponse serveur', () {
    Map<String, dynamic> ligne({String? zone, String? nature, String? logo}) => {
      'rank': 7, 'teamName': 'Real Madrid', 'teamLogo': logo,
      'played': 1, 'win': 1, 'draw': 0, 'lose': 0,
      'goalsDiff': 1, 'points': 3, 'form': 'W',
      'zone': zone, 'zoneNature': nature,
    };

    test('la zone et sa nature sont reprises', () {
      final r = StandingRow.fromJson(
        ligne(zone: 'Ligue des champions', nature: 'c1'));
      expect(r.zone, 'Ligue des champions');
      expect(r.zoneNature, 'c1');
    });

    test('une ligne sans zone reste valide', () {
      final r = StandingRow.fromJson(ligne());
      expect(r.zone, isNull);
      expect(r.zoneNature, isNull);
      expect(r.points, 3);
    });

    // Une version antérieure du serveur ne renvoie pas ces champs : le
    // classement doit rester lisible, simplement sans regroupement.
    test('un serveur plus ancien reste compatible', () {
      final j = ligne()..remove('zone')..remove('zoneNature');
      final r = StandingRow.fromJson(j);
      expect(r.zone, isNull);
      expect(r.teamName, 'Real Madrid');
    });

    test('le logo est conservé', () {
      final r = StandingRow.fromJson(ligne(logo: 'https://x/logo.png'));
      expect(r.teamLogo, 'https://x/logo.png');
    });
  });

  group('ce que l\'écran doit faire de ces champs', () {
    final source = File(
      'lib/features/pronostics/presentation/pages/match_detail/classements.dart',
    ).readAsStringSync();

    // Retirer aussi les commentaires **de fin de ligne**.
    //
    // Ne filtrer que les lignes entièrement commentées laissait passer
    // `'c1' => Color(…),  // Ligue des champions` : le test croyait alors voir
    // un libellé dans la logique de couleur, et échouait sur son propre
    // artefact. Le `(?<!:)` épargne les URL (`https://`).
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .map((l) => l.replaceAll(RegExp(r'(?<!:)//.*$'), ''))
        .join('\n');

    test('l\'écusson est affiché', () {
      expect(code.contains('row.teamLogo'), isTrue,
        reason: 'le logo était récupéré par le serveur et ignoré par l\'écran');
      expect(code.contains('repli:'), isTrue,
        reason: 'un logo introuvable ne doit pas casser la ligne');
    });

    test('les lignes sont regroupées par zone', () {
      expect(code.contains('zonePrecedente'), isTrue,
        reason: 'sans regroupement, la zone se répéterait à chaque ligne');
      expect(code.contains('r.zone'), isTrue);
    });

    // La couleur doit venir de la nature, jamais du libellé : deux
    // championnats nomment différemment la même zone.
    test('la couleur dépend de la nature, pas du libellé', () {
      // On isole le corps du `switch` plutôt qu'une fenêtre de N caractères :
      // une fenêtre déborde sur le code suivant et fait échouer le test sur
      // son propre artefact — ce qui vient d'arriver.
      final debut = code.indexOf('switch (nature)');
      expect(debut, greaterThan(-1), reason: '_couleurZone a changé de forme');
      final fin = code.indexOf('};', debut);
      final corps = code.substring(debut, fin);

      for (final nature in ['c1', 'c3', 'c4', 'relegation', 'barrage']) {
        expect(corps.contains("'$nature'"), isTrue,
          reason: 'nature « $nature » sans couleur associée');
      }

      // Chaque cas doit être une nature connue, jamais un libellé : deux
      // championnats nomment différemment la même zone.
      final cles = RegExp(r"'([^']+)'\s*=>")
          .allMatches(corps).map((m) => m.group(1)!).toSet();
      expect(cles.difference(
        {'c1', 'c3', 'c4', 'barrage', 'promotion', 'relegation'}), isEmpty,
        reason: 'un cas du switch n\'est pas une nature — la couleur ne doit '
                'pas dépendre d\'une chaîne de libellé');
    });

    test('le tableau ne réaffiche plus sept colonnes', () {
      // V, N et D se déduisent des points : sur un écran de téléphone, elles
      // serraient le nom des équipes au point de le tronquer.
      for (final colonne in ["_StandingsHeaderCell('V')",
                             "_StandingsHeaderCell('N')",
                             "_StandingsHeaderCell('D')"]) {
        expect(code.contains(colonne), isFalse,
          reason: 'colonne « $colonne » réintroduite');
      }
      expect(code.contains("_StandingsHeaderCell('Pts')"), isTrue);
    });
  });
}
