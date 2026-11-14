import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Les deux équipes partageaient **un seul terrain**, l'une en miroir de
/// l'autre. Le commentaire du code admettait déjà le prix de ce choix : à onze
/// joueurs par moitié, les photos tombaient à dix-huit pixels et les noms se
/// compressaient dans un `FittedBox`.
///
/// Et l'écusson comme la formation manquaient — ils viennent du match, pas de
/// la réponse `/lineups`, qui ne porte ni nom ni logo d'équipe.
void main() {
  final source = File(
    'lib/features/pronostics/presentation/pages/match_detail/compositions.dart',
  ).readAsStringSync();

  /// Le code sans les commentaires, qui citent volontairement l'ancien état.
  final code = source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .map((l) => l.replaceAll(RegExp(r'(?<!:)//.*$'), ''))
      .join('\n');

  group('un terrain par équipe', () {
    test('le terrain d\'équipe existe', () {
      expect(code.contains('class _TerrainEquipe'), isTrue);
    });

    test('les deux équipes ne partagent plus une seule surface', () {
      // L'ancienne mise en page empilait deux `Expanded` dans un même terrain,
      // ce qui divisait la hauteur par deux.
      final vue = code.indexOf('class _PitchView');
      final fin = code.indexOf('class _TerrainEquipe');
      expect(vue, greaterThan(-1));
      expect(fin, greaterThan(vue));
      expect(code.substring(vue, fin).contains('Expanded'), isFalse,
        reason: 'deux moitiés dans un seul terrain compressent les photos');
    });

    test('chaque équipe est rendue avec son propre terrain', () {
      expect(RegExp(r'_TerrainEquipe\(').allMatches(code).length,
        greaterThanOrEqualTo(2),
        reason: 'domicile et extérieur doivent chacun avoir le leur');
    });

    // J'avais d'abord supprimé le miroir, en croyant qu'il ne servait qu'à
    // faire tenir deux équipes sur une surface. Il porte autre chose : mises
    // bout à bout, les deux moitiés se font face comme un terrain déplié, et
    // chaque équipe attaque vers l'adversaire. Lire les deux dans le même sens
    // supprime cette lecture — le gardien visiteur doit rester en bas.
    test('l\'équipe extérieure est en miroir', () {
      expect(code.contains('miroir: true'), isTrue,
        reason: 'sans renversement, les deux équipes attaquent dans le même '
                'sens et le terrain ne se lit plus comme un terrain');
      final t = code.indexOf('class _TerrainEquipe');
      expect(code.substring(t).contains('rows.reversed'), isTrue);
    });

    test('l\'en-tête de l\'équipe extérieure passe sous son terrain', () {
      final t = code.indexOf('class _TerrainEquipe');
      expect(code.substring(t).contains('miroir ? [terrain, entete] : [entete, terrain]'),
        isTrue,
        reason: 'en miroir, un en-tête au-dessus se retrouverait du côté des '
                'attaquants plutôt que sur le bord extérieur');
    });
  });

  group('ce que l\'en-tête doit porter', () {
    test('l\'écusson de l\'équipe', () {
      expect(code.contains('url:     logo'), isTrue,
        reason: 'le logo vient du match : `/lineups` n\'en renvoie aucun');
      expect(code.contains('repli:   const SizedBox.shrink()'), isTrue,
        reason: 'un logo introuvable ne doit pas casser l\'en-tête');
    });

    test('le nom et la formation', () {
      final t = code.indexOf('class _TerrainEquipe');
      final corps = code.substring(t);
      expect(corps.contains('equipe.formation'), isTrue,
        reason: 'la formation était disponible et jamais affichée');
      expect(corps.contains('Text(nom'), isTrue);
    });

    test('la carte reçoit le match, pas seulement son identifiant', () {
      expect(code.contains('final MatchEntity match;'), isTrue);
      expect(RegExp(r'final String matchId;').hasMatch(code), isFalse,
        reason: 'l\'identifiant seul ne donne accès ni au nom ni au logo');
    });
  });

  group('les entraîneurs', () {
    test('sont présentés avec leur photo', () {
      expect(code.contains('class _CarteEntraineurs'), isTrue);
      expect(code.contains('equipe?.coachPhoto'), isTrue,
        reason: 'la photo accompagnait le nom dans la même réponse et n\'était '
                'pas lue');
    });

    test('une photo absente ne laisse pas de trou', () {
      final c = code.indexOf('class _UnEntraineur');
      final corps = code.substring(c);
      expect(corps.contains('Icons.person_rounded'), isTrue,
        reason: 'il faut une silhouette de repli, de même taille');
      expect(corps.contains('repli:'), isTrue);
    });
  });

  test('les photos peuvent occuper la place rendue disponible', () {
    // Le plafond de 34 px datait du terrain partagé, où onze joueurs tenaient
    // dans une demi-hauteur. Le conserver aurait laissé la place inutilisée.
    final m = RegExp(r'clamp\(([\d.]+),\s*([\d.]+)\)').firstMatch(code);
    expect(m, isNotNull, reason: 'le calcul de taille d\'avatar a changé de forme');
    expect(double.parse(m!.group(2)!), greaterThan(34.0),
      reason: 'plafond hérité du terrain partagé');
  });
}
