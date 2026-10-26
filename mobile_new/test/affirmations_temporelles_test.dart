import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un widget sans données ne doit pas affirmer une date.
///
/// `_EmptyPronostics` — la carte « Pas de prono aujourd'hui » de l'accueil —
/// annonçait « Le prochain match est demain ». C'est un widget `const` sans
/// paramètre : il ne reçoit aucun calendrier, la phrase était une constante.
/// Elle disait donc « demain » tous les jours de l'année.
///
/// Le 2 septembre, elle s'affichait à deux cents pixels d'une carte qui
/// décomptait trois jours jusqu'au prochain match. Deux affirmations
/// contradictoires sur le même écran, dont une fausse par construction.
///
/// « aujourd'hui » reste permis : la carte ne s'affiche que lorsque la liste
/// du jour est vide, donc elle en est la seule chose qu'elle sait vraiment.
/// Ce sont les mots qui portent au-delà du présent qui sont interdits ici.
void main() {
  const chemin =
      'lib/features/accueil/presentation/pages/accueil/squelettes.dart';

  final lignes = File(chemin).readAsLinesSync();

  test('le fichier des états vides existe toujours', () {
    // Sans ancre, le contrôle verdirait sur un fichier renommé.
    expect(lignes.join('\n'), contains('_EmptyPronostics'));
  });

  test('aucun état vide n\'annonce une échéance', () {
    const interdits = ['demain', 'après-demain', 'la semaine prochaine',
                       'dans quelques heures', 'ce soir'];

    final fautes = <String>[];
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i];
      // Les commentaires citent la phrase fautive pour l'expliquer.
      if (ligne.trimLeft().startsWith('//')) continue;
      final bas = ligne.toLowerCase();
      for (final mot in interdits) {
        if (bas.contains(mot)) {
          fautes.add('$chemin:${i + 1} « $mot » — ${ligne.trim()}');
        }
      }
    }

    expect(fautes, isEmpty,
      reason: 'ces widgets ne reçoivent aucune date : toute échéance qu\'ils '
              'annoncent est une constante, vraie un jour et fausse les '
              'autres');
  });
}
