import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// L'onglet Blessures mélangeait deux langues :
///
///     R. Asencio      Blessure musculaire
///     Eder Militao    Hamstring Injury
///     F. Mendy        Hip Injury
///
/// La table de traduction vivait dans l'écran et sa règle était juste — un
/// motif inconnu restait affiché plutôt que masqué. Mais elle avait des trous,
/// et **rien ne les signalait**.
void main() {
  Map<String, dynamic> absence({
    String reason = 'Blessure au genou',
    String? photo,
    bool? suspension,
  }) {
    final j = <String, dynamic>{
      'name': 'R. Asencio', 'team': 'home', 'type': 'Injured',
      'reason': reason,
    };
    // Champs omis quand ils sont nuls : c'est ainsi qu'on simule une réponse
    // d'un serveur antérieur à leur ajout.
    if (photo != null) j['photo'] = photo;
    if (suspension != null) j['suspension'] = suspension;
    return j;
  }

  group('lecture de la réponse serveur', () {
    test('le motif est repris tel quel — il arrive déjà traduit', () {
      final p = InjuredPlayer.fromJson(absence(reason: 'Blessure à la hanche'));
      expect(p.reason, 'Blessure à la hanche');
    });

    test('la photo est conservée', () {
      final p = InjuredPlayer.fromJson(absence(photo: 'https://x/p.png'));
      expect(p.photo, 'https://x/p.png');
    });

    test('la suspension vient du serveur', () {
      expect(InjuredPlayer.fromJson(absence(suspension: true)).suspension, isTrue);
      expect(InjuredPlayer.fromJson(absence(suspension: false)).suspension, isFalse);
    });

    // Une version antérieure du serveur ne renvoie ni photo ni drapeau : la
    // liste doit rester lisible, et la suspension se déduire du motif comme
    // l'écran le faisait auparavant.
    test('un serveur plus ancien reste compatible', () {
      final p = InjuredPlayer.fromJson(absence(reason: 'Red Card'));
      expect(p.photo, isNull);
      expect(p.suspension, isTrue,
        reason: 'repli sur le motif quand le drapeau manque');
    });
  });

  group('ce que l\'écran ne doit plus faire', () {
    final code = File(
      'lib/features/pronostics/presentation/pages/match_detail/blessures.dart',
    ).readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
        .join('\n');

    test('plus de table de traduction locale', () {
      expect(code.contains('_reasons'), isFalse,
        reason: 'la traduction se fait à la frontière du fournisseur, où un '
                'motif inconnu se journalise au lieu de finir à l\'écran');
      expect(code.contains("'knee injury'"), isFalse);
    });

    test('le motif affiché est celui du serveur', () {
      expect(code.contains('Text(player.reason'), isTrue);
      expect(code.contains('Text(_label'), isFalse);
    });

    test('la photo du joueur est affichée', () {
      expect(code.contains('player.photo'), isTrue,
        reason: 'elle était fournie par l\'API et jamais lue');
      // `repli:` a remplacé `errorBuilder:` : la photo passe par
      // `ImageDistante`, qui décode à la taille d'affichage et exige un repli
      // — la propriété est la même, elle est simplement devenue obligatoire.
      expect(code.contains('ImageDistante('), isTrue,
        reason: 'décoder une photo de 500 px pour un rond de 26 coûte de la '
                'mémoire sur les appareils que vise l\'application');
      expect(code.contains('repli:'), isTrue,
        reason: 'une photo introuvable ne doit pas casser la ligne');
    });
  });
}
