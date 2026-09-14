import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/parametres/presentation/pages/legal_page.dart';

/// Les conditions générales du site sont celles de l'application.
///
/// Le même contrat est rendu à deux endroits : la page embarquée dans
/// l'application, et `/cgu` sur le site — le lien donné depuis le paywall,
/// celui qu'un utilisateur ouvre au moment de décider s'il paie, et celui
/// qu'un examinateur ouvre après l'URL de confidentialité.
///
/// La politique de confidentialité avait déjà montré ce que devient un texte
/// juridique recopié : deux rédactions, deux dates de révision indépendantes,
/// et l'application déclarant trois catégories de données là où le site en
/// détaillait cinq. Le texte des conditions générales n'est donc pas recopié —
/// il est exporté depuis `sectionsLegales()` par `tool/exporter_cgu.dart`, et
/// ce contrôle refuse tout écart.
///
/// La comparaison est **exacte**, pas thématique. Il ne s'agit pas ici de deux
/// textes écrits pour deux publics — comme pour la confidentialité — mais d'un
/// seul texte servi deux fois. Un mot qui change d'un côté et pas de l'autre
/// est un contrat qui existe en deux versions.
void main() {
  const chemin = '../website/content/cgu.json';
  const regenerer = 'flutter test tool/exporter_cgu.dart';

  late Map<String, dynamic> site;

  setUpAll(() {
    final f = File(chemin);
    // Pas de `skip` si le fichier manque : un contrôle qui s'efface quand il
    // ne peut pas travailler finit par ne plus rien garder.
    expect(f.existsSync(), isTrue,
        reason: '$chemin introuvable — lancez « $regenerer »');
    site = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  });

  for (final (canal, estStore) in [('direct', false), ('store', true)]) {
    test('canal $canal : le site publie le texte de l\'application', () {
      final attendu = sectionsLegales(LegalType.cgu, estStore: estStore);
      final publie  = (site[canal] as List?) ?? const [];

      expect(publie.length, attendu.length,
          reason: 'le site publie ${publie.length} articles pour le canal '
                  '$canal, l\'application en a ${attendu.length} — '
                  'lancez « $regenerer »');

      for (var i = 0; i < attendu.length; i++) {
        final a = attendu[i];
        final p = publie[i] as Map<String, dynamic>;
        expect(p['titre'], a.title,
            reason: 'article ${i + 1} du canal $canal : titre différent — '
                    'lancez « $regenerer »');
        expect(p['texte'], a.content,
            reason: 'article ${i + 1} du canal $canal (« ${a.title} ») : '
                    'le texte publié diffère de celui de l\'application — '
                    'lancez « $regenerer »');
      }
    });
  }

  test('le canal store ne publie pas l\'article partenaire', () {
    // Cette différence est la raison d'être des deux listes. Si l'export les
    // rendait identiques, les contrôles ci-dessus passeraient toujours — et le
    // site publierait, sous notre propre lien, l'article que la version des
    // boutiques a retiré.
    final store  = jsonEncode(site['store']);
    final direct = jsonEncode(site['direct']);

    expect(store.contains('1xBet'), isFalse,
        reason: 'le canal store ne doit pas décrire l\'activation partenaire : '
                'elle n\'existe pas dans ce build, et c\'est cet article qui '
                'ferait classer l\'application dans une catégorie réservée '
                'aux organisations');
    expect(direct.contains('1xBet'), isTrue,
        reason: 'le canal direct doit la décrire : c\'est une voie '
                'd\'activation réellement proposée à ses utilisateurs');
  });

  test('la date de révision affichée est celle du site', () {
    // Trois documents partageaient une seule date. Modifier les conditions
    // générales faisait vieillir la politique de confidentialité, dont la date
    // doit rester celle du site : c'est l'URL déclarée à Google.
    final source = File('lib/features/parametres/presentation/pages/legal_page.dart')
        .readAsStringSync();
    final serveur = File('../website/server.js').readAsStringSync();

    // Le fichier contient trois `switch (type)` : titre, sous-titre, date. On
    // isole celui des dates — la première version lisait le premier venu et
    // comparait « Conditions d'utilisation » à une date, en passant pour un
    // vrai échec.
    final bloc = RegExp(
      r'String get _lastUpdated => switch \(type\) \{([^}]*)\}',
    ).firstMatch(source);
    expect(bloc, isNotNull, reason: '_lastUpdated introuvable');
    final app = bloc!.group(1)!;

    for (final (cle, constante) in [
      ('LegalType.cgu', 'MAJ_CGU'),
      ('LegalType.confidentialite', 'MAJ_CONFIDENTIALITE'),
    ]) {
      final dansApp = RegExp('$cle\\s*=>\\s*\'([^\']+)\'').firstMatch(app);
      final dansSite = RegExp('const $constante = \'([^\']+)\'').firstMatch(serveur);
      expect(dansApp, isNotNull, reason: 'date de $cle introuvable');
      expect(dansSite, isNotNull, reason: '$constante introuvable dans server.js');
      expect(dansApp!.group(1), dansSite!.group(1),
          reason: 'l\'application affiche « ${dansApp.group(1)} » et le site '
                  '« ${dansSite.group(1)} » pour le même document');
    }
  });
}
