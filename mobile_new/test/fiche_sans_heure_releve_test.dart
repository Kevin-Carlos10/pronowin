import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ni heure de relevé (« Actualisé à 21:04 ») ni rythme d'actualisation
/// (« toutes les 2 minutes ») dans la fiche du match : Sofascore n'en montre
/// aucun (demandes du 18 et du 20 octobre 2026). Seuls restent les
/// avertissements d'une donnée qui n'arrive plus.
void main() {
  test('aucune mention d\'actualisation dans la fiche, hors avertissements', () {
    final fichiers = [
      File('lib/features/pronostics/presentation/pages/match_detail_page.dart'),
      ...Directory('lib/features/pronostics/presentation/pages/match_detail')
          .listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      File('lib/features/pronostics/presentation/widgets/fil_evenements.dart'),
      File('lib/features/pronostics/presentation/widgets/comments_section.dart'),
    ];
    const permis = {
      'Score non actualisé',
      'Score non actualisé depuis {arg0} min',
      'Actualisation interrompue · dernières données reçues',
    };
    final chaines = RegExp(r'''tr\(\s*context\s*,\s*"([^"]*)"''');
    final fautifs = <String>[];
    for (final f in fichiers) {
      for (final m in chaines.allMatches(f.readAsStringSync())) {
        final texte = m.group(1)!;
        if (RegExp(r'actualis|mis à jour|mise à jour', caseSensitive: false).hasMatch(texte) && !permis.contains(texte)) {
          fautifs.add('${f.path} : « $texte »');
        }
      }
    }
    expect(fautifs, isEmpty);
  });
}
