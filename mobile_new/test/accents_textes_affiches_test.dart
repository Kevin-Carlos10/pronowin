import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les textes affichés portent leurs accents.
///
/// La carte de bankroll écrivait « +4 668 FCFA depuis le depart » sur l'écran
/// du compte, et « Définis ton budget et suis tes gains réels » sans un seul
/// accent. Ce n'était pas une faute de frappe isolée : les commentaires de
/// cette zone du fichier sont eux aussi écrits sans accents, et les chaînes ont
/// suivi. Une relecture ne l'attrape pas — l'œil lit le mot, pas ses accents.
///
/// Un utilisateur, lui, le voit. C'est la première chose qui distingue un
/// produit soigné d'un produit bâclé, sur un écran par ailleurs très soigné.
///
/// ── Ce que ce contrôle regarde, et ce qu'il ignore ─────────────────────────
///
/// Uniquement les **chaînes**, jamais les commentaires ni les identifiants :
/// une variable nommée `depart` ou un commentaire sans accents ne gênent
/// personne. Sont écartés les chemins, les clés et les noms de fichiers, où
/// l'absence d'accent est volontaire.
///
/// La liste des mots est courte et ne contient que des formes qui portent
/// **toujours** un accent en français. Elle n'a pas vocation à couvrir la
/// langue : elle couvre ce qui est déjà arrivé, et ce qui arrivera de la même
/// façon.
void main() {
  /// Formes sans accent qui ne peuvent pas être correctes dans une phrase.
  const motsFautifs = [
    'depart', 'reel', 'reels', 'definis', 'deja', 'apres', 'tres',
    'donnees', 'annee', 'verifie', 'verifier', 'reussite', 'resultat',
    'resultats', 'derniere', 'premiere', 'telecharge', 'telecharger',
    'parametres', 'elements', 'configuree', 'securite', 'preference',
    'validee', 'creer', 'supprimee', 'terminee', 'activee',
  ];

  /// Les chaînes d'un fichier Dart, hors commentaires et hors identifiants.
  ///
  /// L'expression est volontairement simple : elle ne gère pas les
  /// apostrophes échappées, et s'arrête donc parfois au milieu d'une phrase.
  /// C'est sans conséquence ici — on cherche un mot, pas une phrase entière.
  List<String> chainesDe(String source) {
    final chaines = <String>[];
    for (final ligne in source.split('\n')) {
      final nu = ligne.trimLeft();
      if (nu.startsWith('//') || nu.startsWith('*')) continue;
      for (final m in RegExp("'([^']{4,})'").allMatches(ligne)) {
        final s = m.group(1)!;
        // Chemins, clés de stockage, noms de fichiers : pas de la prose.
        if (s.contains('/') || s.contains('_') || s.contains('.dart')) continue;
        // Les identifiants en tirets non plus — `Key('bankroll-resultat-net')`
        // ne s'affiche jamais. Le commentaire en tête annonçait déjà que les
        // clés étaient écartées ; seules celles en `_` l'étaient réellement,
        // et une clé en tirets faisait tomber ce contrôle pour un mot que
        // personne ne lit.
        if (RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$').hasMatch(s)) continue;
        chaines.add(s);
      }
    }
    return chaines;
  }

  test('aucun mot français ne perd ses accents dans un texte affiché', () {
    final fautifs = <String>[];
    var chainesLues = 0;

    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final s in chainesDe(f.readAsStringSync())) {
        chainesLues++;
        final mots = s
            .toLowerCase()
            .split(RegExp('[^a-zàâçéèêëîïôûùüÿñæœ]+'))
            .where((m) => m.isNotEmpty);
        for (final mot in mots) {
          if (motsFautifs.contains(mot)) {
            fautifs.add('${f.path} : « $s »');
            break;
          }
        }
      }
    }

    // Contrepartie : une expression qui ne lirait plus aucune chaîne ferait
    // passer ce contrôle sans avoir rien regardé.
    expect(chainesLues, greaterThan(500),
        reason: 'seulement $chainesLues chaînes lues : la lecture a cassé');

    expect(fautifs, isEmpty,
        reason: 'ces textes s\'affichent sans leurs accents :\n'
                '${fautifs.join('\n')}');
  });

  test('la liste de mots reconnaît bien une faute', () {
    // Sans ce point, vider `motsFautifs` rendrait le contrôle précédent
    // définitivement vert.
    expect(chainesDe("Text('depuis le depart')"), contains('depuis le depart'));
    expect(motsFautifs, contains('depart'));

    // Et il ne confond pas un texte correct avec une faute.
    final correct = chainesDe("Text('depuis le départ')").single;
    final mots = correct
        .toLowerCase()
        .split(RegExp('[^a-zàâçéèêëîïôûùüÿñæœ]+'))
        .where((m) => m.isNotEmpty);
    expect(mots.any(motsFautifs.contains), isFalse);
  });
}
