import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Aucun sigle non expliqué dans le texte affiché.
///
/// « ROI » se lisait à cinq endroits, dont trois écrits pour des gens qui
/// découvrent l'app : l'accueil du Bankroll vide, l'onboarding, et l'écran
/// invité. Un sigle y est un mur — celui qui ne le connaît pas ne peut même pas
/// deviner qu'il s'agit d'argent. Rien ne casse, rien n'échoue : la personne
/// referme l'app.
///
/// Ce contrôle relit les chaînes littérales du code pour que le terme ne
/// revienne pas par une formulation ajoutée plus tard.
void main() {
  /// Sigles à bannir du texte affiché, avec leur remplacement attendu.
  ///
  /// `H2H` a échappé au premier passage parce que seul `ROI` était surveillé.
  /// C'est pourtant le même défaut, en pire : un sigle **anglais**
  /// (head-to-head) sur l'écran d'accueil, là où le lecteur ne connaît encore
  /// rien du produit.
  const bannis = {
    'ROI': 'rentabilité',
    'H2H': 'confrontations directes',
  };

  /// Formules interdites dans le texte affiché : elles affirment un rang ou un
  /// résultat que rien n'établit.
  ///
  /// Deux raisons, et la première est interne : l'article 6 des CGU de
  /// PronoWin écrit noir sur blanc que les pronostics « ne constituent en
  /// aucun cas une garantie de résultat » — pendant que l'onboarding
  /// promettait « des milliers de parieurs **qui gagnent** ». L'app se
  /// contredisait elle-même, et l'écran vu par tout nouvel arrivant portait la
  /// version fausse.
  ///
  /// La seconde est externe : Apple, règle 2.3.1, « marketing your app in a
  /// misleading way … is grounds for removal of your app from the App Store
  /// … and termination of your developer account ».
  final revendications = <RegExp, String>{
    RegExp(r"n\s*°\s*1", caseSensitive: false): 'revendication de rang',
    RegExp(r'\bqui gagnent\b', caseSensitive: false): 'promesse de gain',
    RegExp(r'\bgains? garantis?\b', caseSensitive: false): 'promesse de gain',
    RegExp(r'\b100\s*% de r[ée]ussite\b', caseSensitive: false): 'promesse de gain',
    // L'app ne couvre que le football : une seule source de données
    // (v3.football.api-sports.io) et huit compétitions. Nommer un autre sport
    // dans l'interface promet un contenu qui n'existe pas — et se vérifie en
    // ouvrant l'onglet Pronostics.
    RegExp(r'\b(basket-?ball|tennis|rugby|handball)\b', caseSensitive: false):
        'sport non couvert par l\'app',
  };

  test('aucun sigle opaque dans les chaînes affichées', () {
    final fautifs = <String>[];

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final f in dartFiles) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final l = lignes[i];

        // Les commentaires ont le droit de nommer le sigle — c'est même utile
        // pour expliquer pourquoi il a été retiré.
        final code = l.trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;

        for (final sigle in bannis.keys) {
          // Uniquement dans une chaîne littérale : `perf.roi` est un nom de
          // champ, il ne s'affiche pas.
          final dansTexte = RegExp("'[^']*\\b$sigle\\b[^']*'");
          if (dansTexte.hasMatch(l)) {
            fautifs.add('${f.path.replaceAll('\\', '/')}:${i + 1} — '
                '« $sigle » (préférer « ${bannis[sigle]} »)');
          }
        }
      }
    }

    expect(fautifs, isEmpty,
        reason: 'Sigles non expliqués dans le texte affiché :\n'
            '${fautifs.join('\n')}');
  });

  test('aucune revendication de rang ni promesse de gain', () {
    final fautifs = <String>[];

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final f in dartFiles) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final code = lignes[i].trimLeft();
        // Les commentaires ont le droit de citer la formule pour dire pourquoi
        // elle a été retirée — c'est même le cas juste au-dessus.
        if (code.startsWith('//') || code.startsWith('///')) continue;

        for (final entree in revendications.entries) {
          for (final chaine in RegExp("'((?:[^'\\\\]|\\\\.)*)'")
              .allMatches(lignes[i])
              .map((m) => m.group(1) ?? '')) {
            if (entree.key.hasMatch(chaine)) {
              fautifs.add('${f.path.replaceAll('\\', '/')}:${i + 1} — '
                  '${entree.value} : « $chaine »');
            }
          }
        }
      }
    }

    expect(fautifs, isEmpty,
        reason: 'Affirmations que rien n\'établit, et que les CGU de l\'app '
            'contredisent :\n${fautifs.join('\n')}');
  });
}
