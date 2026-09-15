import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/parametres/presentation/pages/legal_page.dart';

/// Exporte les conditions générales vers le site.
///
///     flutter test tool/exporter_cgu.dart
///
/// Le texte est écrit une seule fois, dans `legal_page.dart`, et rendu à deux
/// endroits : la page embarquée dans l'application et `/cgu` sur le site. Le
/// site n'avait aucune page de conditions générales — alors que c'est le lien
/// donné depuis le paywall, là où Apple exige des liens *fonctionnels*
/// (3.1.2), et la première page qu'un examinateur ouvre après l'URL de
/// confidentialité.
///
/// Le recopier à la main aurait créé un second original. C'est exactement ce
/// qui était arrivé à la politique de confidentialité : deux textes, deux
/// dates de révision, et l'application déclarant trois catégories de données
/// là où le site en détaillait cinq.
///
/// Ce fichier vit dans `tool/` et non dans `test/` : il écrit un fichier du
/// dépôt, ce qu'une suite de tests ne doit pas faire en passant.
/// `cgu_site_coherent_test.dart` vérifie le résultat et renvoie ici quand il
/// a dérivé.
void main() {
  const destination = '../website/content/cgu.json';

  test('exporte les conditions générales vers $destination', () {
    final contenu = <String, dynamic>{};

    // Les deux canaux, parce que le texte diffère : la version des boutiques
    // ne publie pas l'article consacré à l'activation par code partenaire.
    for (final estStore in [false, true]) {
      contenu[estStore ? 'store' : 'direct'] =
          sectionsLegales(LegalType.cgu, estStore: estStore)
              .map((s) => {'titre': s.title, 'texte': s.content})
              .toList();
    }

    final fichier = File(destination);
    expect(fichier.parent.existsSync(), isTrue,
        reason: '${fichier.parent.path} introuvable — le site et '
                'l\'application vivent dans le même dépôt');

    fichier.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(contenu)}\n');

    final direct = (contenu['direct'] as List).length;
    final store  = (contenu['store']  as List).length;
    // ignore: avoid_print
    print('  $destination écrit : $direct articles (direct), $store (store)');
  });
}
