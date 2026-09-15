import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les ressources d'aide au jeu doivent servir d'abord ceux qui lisent.
///
/// La section « Ressources d'aide » ouvrait ainsi :
///
///     🇫🇷 France — Joueurs Info Service : 09 74 75 13 13
///     🌐 Gamblers Anonymous (international)
///     🌍 Hors France : rapprochez-vous d'un professionnel de santé
///
/// PronoWin s'adresse d'abord au Burkina Faso. La seule entrée concrète de
/// cette liste était donc un numéro que la quasi-totalite des lecteurs ne peut
/// pas composer, et ce qui les concernait tenait en une phrase sans indication
/// de qui aller voir.
///
/// Ce n'est pas une question de ton : quelqu'un qui ouvre cette page va mal, et
/// la première chose qu'il lit doit être quelque chose qu'il peut faire. Un
/// numéro etranger en tête de liste lui apprend surtout que la page n'a pas ete
/// ecrite pour lui.
///
/// Ce contrôle ne juge pas le contenu — il vérifie l'ordre : ce qui marche
/// partout doit précéder ce qui dépend d'un pays.
void main() {
  final source = File(
    'lib/features/parametres/presentation/pages/legal_page.dart',
  ).readAsStringSync();

  /// Le corps de la section, isolé de la page.
  String sectionAide() {
    final debut = source.indexOf('Ressources d\\\'aide');
    expect(debut, greaterThan(0), reason: 'section « Ressources d\'aide » introuvable');
    final fin = source.indexOf('LegalSection', debut + 1);
    return source.substring(debut, fin == -1 ? source.length : fin);
  }

  test('l\'aide accessible partout précède les ressources d\'un seul pays', () {
    final texte = sectionAide();

    // Ce qu'on peut faire quel que soit le pays.
    final universel = texte.indexOf('Où que vous soyez');
    // Une ressource rattachée à un pays donné — ici la France, reconnaissable
    // à son indicatif. Le motif ne cite pas le drapeau : il peut disparaître
    // sans que la ressource cesse d'être nationale.
    final national = RegExp(r'France\s*—|0\d(?:\s\d\d){4}').firstMatch(texte)?.start ?? -1;

    expect(universel, greaterThan(0),
      reason: 'aucune aide actionnable indépendamment du pays');
    expect(national, greaterThan(0),
      reason: 'la ressource nationale a disparu — ce contrôle ne vérifie plus '
              'rien, revoir son motif plutôt que de le supprimer');
    expect(universel, lessThan(national),
      reason: 'la ressource d\'un seul pays arrive avant ce qui marche '
              'partout : le lecteur lit d\'abord ce qu\'il ne peut pas faire');
  });

  test('elle oriente vers des personnes joignables, pas vers une abstraction', () {
    final texte = sectionAide();

    // « rapprochez-vous d'un professionnel de santé » ne dit pas qui aller
    // voir. Ces mots-là, si.
    const concrets = ['médecin', 'psychologue', 'hôpital', 'centre de santé'];
    final presents = concrets.where(texte.contains).toList();

    expect(presents.length, greaterThanOrEqualTo(3),
      reason: 'la page doit nommer des interlocuteurs réels ; trouvés : '
              '$presents');
  });

  test('elle rappelle qu\'on peut en parler à un proche', () {
    // La ressource la plus disponible, partout, gratuitement — et celle que
    // les listes de numéros oublient systématiquement.
    expect(sectionAide(), contains('confiance'),
      reason: 'en parler à quelqu\'un reste ce qui change le plus, et c\'est '
              'la seule chose accessible à tous sans condition');
  });
}
