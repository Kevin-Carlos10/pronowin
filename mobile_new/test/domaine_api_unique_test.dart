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
///   - `_productionHost` dans `dio_client.dart`, qui décidait sur quel hôte
///     l'épinglage de certificat s'appliquait (retiré depuis, voir plus bas).
///
/// Ce domaine n'existe pas. Nginx ne sert que `pronowin.space`,
/// `www.pronowin.space` et l'IP ; l'API vit sous `pronowin.space/api/`. Il n'y
/// a aucun sous-domaine `api.`, ni en `.com`, ni en `.space`.
///
/// ── Pourquoi rien ne l'avait signalé ──────────────────────────────────────
///
/// Les occurrences étaient invisibles à l'exécution normale. Les exemples de
/// `build.ps1` sont du commentaire, et `_productionHost` n'était lu que dans
/// une branche que rien ne déclenchait. Ni la compilation, ni `flutter
/// analyze`, ni les tests ne lisent une chaîne de caractères pour vérifier
/// qu'elle désigne une machine réelle.
///
/// Le seul endroit qui connaissait la bonne adresse était
/// `tool/verifier_bundle.py`, qui ouvre l'artefact produit et refuse de le
/// laisser partir si l'URL embarquée n'est pas la bonne. C'est lui qui aurait
/// rattrapé une release construite sur l'exemple faux — après coup, au prix
/// d'un build.
///
/// ── Ce que ce banc tient ──────────────────────────────────────────────────
///
/// Les fichiers doivent nommer le même hôte. Aucun n'est la source de vérité
/// des autres : ils se contrôlent mutuellement, de sorte qu'un changement de
/// domaine fait tomber le banc tant qu'il n'est pas répercuté partout.
void main() {
  String lire(String chemin) => File(chemin).readAsStringSync();

  /// Le domaine partagé, [AppConstants.domaine].
  ///
  /// L'épinglage de certificat qui le lisait a été retiré (M7) ; le domaine,
  /// lui, reste la référence de tout ce qui nomme l'API.
  String hoteDomaine() {
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

  group('les fichiers nomment le même hôte', () {
    test('le domaine partagé est celui que l\'artefact doit contenir', () {
      expect(hoteDomaine(), hoteArtefact());
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

  group('pas d\'épinglage factice (M7)', () {
    // Un bloc « épinglage » reposait sur `badCertificateCallback`, que Dart
    // n'appelle qu'après l'échec de la validation : un certificat valablement
    // signé par une autorité compromise — la menace même — passait sans
    // l'éveiller. Il a été retiré le 25 septembre 2026. S'il revenait sous
    // cette forme, il paraîtrait protéger et ne protégerait rien.
    test('aucune ligne active ne s\'appuie sur badCertificateCallback', () {
      final actives = lire('lib/core/network/dio_client.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'));
      expect(actives.where((l) => l.contains('badCertificateCallback')), isEmpty,
          reason: 'un épinglage par badCertificateCallback ne vérifie rien : '
              'passer par network_security_config.xml (voir dio_client.dart)');
    });

    test('la décision reste écrite là où l\'on chercherait', () {
      expect(lire('lib/core/network/dio_client.dart'),
          contains("Pas d'épinglage de certificat"));
    });
  });
}
