import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un seul domaine d'API, écrit pareil partout.
///
/// ── Ce qui était écrit ────────────────────────────────────────────────────
///
/// Quatre lignes, dans deux fichiers, portaient `api.pronowin.com` :
///
///   - les deux exemples de la documentation de `tool/build.ps1`, ceux qu'on
///     copie pour lancer une release ;
///   - `_productionHost` dans `dio_client.dart`, qui décide sur quel hôte
///     l'épinglage de certificat s'applique.
///
/// Ce domaine n'existe pas. Nginx ne sert que `pronowin.space`,
/// `www.pronowin.space` et l'IP ; l'API vit sous `pronowin.space/api/`. Il n'y
/// a aucun sous-domaine `api.`, ni en `.com`, ni en `.space`.
///
/// ── Pourquoi rien ne l'avait signalé ──────────────────────────────────────
///
/// Les deux occurrences sont invisibles à l'exécution normale. Les exemples de
/// `build.ps1` sont du commentaire, et `_productionHost` n'est lu que dans une
/// branche que rien ne déclenche — l'épinglage est inerte, liste d'empreintes
/// vide. Ni la compilation, ni `flutter analyze`, ni les tests ne lisent une
/// chaîne de caractères pour vérifier qu'elle désigne une machine réelle.
///
/// Le seul endroit qui connaissait la bonne adresse était
/// `tool/verifier_bundle.py`, qui ouvre l'artefact produit et refuse de le
/// laisser partir si l'URL embarquée n'est pas la bonne. C'est lui qui aurait
/// rattrapé une release construite sur l'exemple faux — après coup, au prix
/// d'un build.
///
/// ── Ce que ce banc tient ──────────────────────────────────────────────────
///
/// Les trois fichiers doivent nommer le même hôte. Aucun n'est la source de
/// vérité des deux autres : ils se contrôlent mutuellement, de sorte qu'un
/// changement de domaine fait tomber le banc tant qu'il n'est pas répercuté
/// partout.
void main() {
  String lire(String chemin) => File(chemin).readAsStringSync();

  /// L'hôte visé par l'épinglage.
  ///
  /// `_productionHost` doit *lire* [AppConstants.domaine], jamais réécrire le
  /// domaine. Une copie à la main est ce qui avait laissé `api.pronowin.com`
  /// survivre — et en la corrigeant, le premier réflexe a été d'en écrire une
  /// seconde, que `domaine_partage_test.dart` a rattrapée.
  String hoteEpinglage() {
    final s = lire('lib/core/network/dio_client.dart');
    expect(s, contains('_productionHost = AppConstants.domaine'),
        reason: '_productionHost doit lire la constante partagée, '
            'pas porter sa propre copie du domaine');

    final c = lire('lib/core/constants/app_constants.dart');
    final m = RegExp(r"String\s+domaine\s*=\s*'([^']+)'").firstMatch(c);
    expect(m, isNotNull, reason: 'AppConstants.domaine est introuvable');
    return m!.group(1)!;
  }

  /// L'hôte de l'URL que `verifier_bundle.py` exige dans l'artefact.
  String hoteArtefact() {
    final s = lire('tool/verifier_bundle.py');
    final m = RegExp(r"ATTENDU\s*=\s*'([^']+)'").firstMatch(s);
    expect(m, isNotNull,
        reason: 'ATTENDU est introuvable dans tool/verifier_bundle.py');
    return Uri.parse(m!.group(1)!).host;
  }

  /// Les hôtes proposés par les exemples de `build.ps1`.
  Set<String> hotesExemples() {
    final s = lire('tool/build.ps1');
    final trouves = RegExp(r'-ApiUrl\s+(https?://\S+)')
        .allMatches(s)
        .map((m) => Uri.parse(m.group(1)!).host)
        .toSet();
    expect(trouves, isNotEmpty,
        reason: 'aucun exemple -ApiUrl dans tool/build.ps1');
    return trouves;
  }

  group('les trois fichiers nomment le même hôte', () {
    test('l\'épinglage vise l\'hôte que l\'artefact doit contenir', () {
      // Si ces deux-là divergent, l'épinglage porte sur une machine que
      // l'application ne contacte jamais : activé, il ne protégerait rien.
      expect(hoteEpinglage(), hoteArtefact());
    });

    test('les exemples de build.ps1 mènent au même hôte', () {
      // C'est la ligne qu'on copie pour produire une release. Un exemple faux
      // est un piège écrit dans la documentation de l'outil lui-même.
      for (final h in hotesExemples()) {
        expect(h, hoteArtefact());
      }
    });
  });

  group('le domaine inexistant n\'est plus employé', () {
    /// Les lignes qui agissent, commentaires retirés.
    ///
    /// Les commentaires *citent* `api.pronowin.com` à dessein : expliquer ce
    /// qui était faux demande de l'écrire. Leur interdire la mention rendrait
    /// le code moins compréhensible sans rien protéger — ce qui compte est
    /// qu'aucune ligne active ne s'en serve.
    String actif(String source, String marqueur) => source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith(marqueur))
        .join('\n');

    test('aucune ligne active ne porte api.pronowin.com', () {
      // Domaine jamais enregistré : nginx ne sert que pronowin.space,
      // www.pronowin.space et l'IP.
      final cas = {
        'lib/core/network/dio_client.dart': '//',
        'tool/verifier_bundle.py': '#',
      };
      cas.forEach((chemin, marqueur) {
        expect(actif(lire(chemin), marqueur), isNot(contains('api.pronowin.com')),
            reason: '$chemin s\'en sert encore');
      });
    });

    test('aucun exemple de build.ps1 n\'y renvoie', () {
      // Ceux-ci vivent dans le bloc d'aide `<# … #>`, donc en commentaire — et
      // ce sont pourtant eux qu'on copie pour lancer une release. Le contrôle
      // porte sur la ligne entière, commentaire ou non.
      expect(lire('tool/build.ps1'), isNot(contains('api.pronowin.com')));
    });
  });

  group('l\'épinglage reste déclaré inerte tant qu\'il ne marche pas', () {
    // `badCertificateCallback` n'est appelé par Dart que lorsque la validation
    // a *déjà* échoué. Un attaquant muni d'un certificat valablement signé —
    // la menace même que l'épinglage vise — passe la validation, donc le
    // callback ne s'exécute pas. Remplir les empreintes donnerait l'apparence
    // d'une protection sans en fournir une.
    test('la liste d\'empreintes est vide, et le commentaire le dit', () {
      final s = lire('lib/core/network/dio_client.dart');

      final bloc = RegExp(r'_pinnedSha256\s*=\s*<String>\{(.*?)\};', dotAll: true)
          .firstMatch(s);
      expect(bloc, isNotNull);
      final actives = bloc!
          .group(1)!
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'));
      expect(actives, isEmpty,
          reason: 'des empreintes ont été ajoutées : relire pourquoi le '
              'mécanisme ne peut pas les faire respecter');

      expect(s, contains('INERTE'),
          reason: 'l\'avertissement en tête du bloc a disparu');
    });
  });
}
