import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Cohérence de la configuration d'intégration continue.
///
/// `codemagic.yaml` porte l'identifiant client Google en clair — il est public
/// par nature, embarqué dans l'app. Mais il y est **recopié**, et une copie
/// finit toujours par diverger de sa source.
///
/// La divergence ne casse aucun build : la CI compile, produit un `.ipa`
/// parfaitement valide, et la connexion Google y échoue à l'exécution avec un
/// message que rien ne relie à ce fichier. C'est précisément le genre de panne
/// qu'un test doit couvrir, faute de pouvoir la voir.
void main() {
  final racine = Directory.current.path.endsWith('mobile_new')
      ? Directory.current.parent
      : Directory.current;
  final fichierCi = File('${racine.path}/codemagic.yaml');

  late YamlMap ci;

  setUpAll(() {
    ci = loadYaml(fichierCi.readAsStringSync()) as YamlMap;
  });

  test('le fichier existe et se lit', () {
    expect(fichierCi.existsSync(), isTrue);
    expect(ci['workflows'], isNotNull);
  });

  test('les deux plateformes ont leur workflow', () {
    final w = (ci['workflows'] as YamlMap).keys.cast<String>().toList();
    expect(w, contains('ios-verification'));
    expect(w, contains('android-release'));
  });

  test('l\'identifiant Google du YAML est celui de google-services.json', () {
    final json = jsonDecode(
        File('android/app/google-services.json').readAsStringSync()) as Map;

    final app = (json['client'] as List).firstWhere((c) =>
        c['client_info']['android_client_info']['package_name'] ==
        'com.pronowin.app');
    final clientWeb = (app['oauth_client'] as List)
        .firstWhere((o) => o['client_type'] == 3)['client_id'] as String;

    // On cherche la valeur n'importe où dans le fichier plutôt que de suivre
    // le chemin des ancres YAML : elle doit y être, peu importe la structure.
    expect(fichierCi.readAsStringSync(), contains(clientWeb),
        reason: 'codemagic.yaml annonce un autre identifiant que '
                'google-services.json — la connexion Google échouera');
  });

  test('la version de Flutter est figée, jamais « stable »', () {
    // « stable » suit les mises à jour du canal : un build qui passe
    // aujourd'hui peut échouer demain sans qu'une ligne du projet ait bougé.
    for (final entree in (ci['workflows'] as YamlMap).entries) {
      final v = entree.value['environment']['flutter'];
      expect(v, isNot('stable'), reason: '${entree.key} suit un canal mouvant');
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch('$v'), isTrue,
          reason: '${entree.key} : « $v » n\'est pas une version figée');
    }
  });

  test('aucun secret n\'est écrit en clair dans le YAML', () {
    // Les deux fichiers de configuration contiennent des clés d'API et
    // n'entrent dans la CI que par variables sécurisées. Les voir apparaître
    // ici signifierait qu'ils ont été collés dans un dépôt public.
    final src = fichierCi.readAsStringSync();
    expect(src, isNot(contains('AIzaSy')),
        reason: 'une clé d\'API Google figure en clair');
    expect(src, isNot(contains('BEGIN PRIVATE KEY')));
  });

  test('le build iOS vérifie que le plist arrive dans le bundle', () {
    // Le contrôle central : c'est l'absence de ce fichier du bundle qui
    // faisait échouer Firebase au démarrage, sans que rien ne le signale à la
    // compilation. Retirer cette étape rendrait la CI aveugle au défaut
    // qu'elle existe pour détecter.
    final etapes = (ci['workflows']['ios-verification']['scripts'] as YamlList)
        .map((s) => '${s['script']}')
        .join('\n');
    expect(etapes, contains('GoogleService-Info.plist'));
    expect(etapes, contains('ajouter_plist_xcode.rb'));
  });
}
