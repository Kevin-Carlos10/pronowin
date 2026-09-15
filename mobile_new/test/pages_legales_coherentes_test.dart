import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/pages_legales.dart';

/// Les textes légaux s'ouvrent tous de la même façon.
///
/// Trois comportements coexistaient pour trois liens qui font la même chose :
///
///  - le paywall ouvrait le navigateur du système ;
///  - les Paramètres ouvraient une copie embarquée dans l'application ;
///  - « Mentions légales », dans ces mêmes Paramètres, ouvrait la page du site
///    dans une webview interne.
///
/// Aucun de ces trois n'était accidentel pris isolément ; ensemble ils ne
/// suivaient aucune règle. Ils ouvrent désormais tous le navigateur du
/// système, sur la page publique — celle qu'on cite, qu'un examinateur ouvre,
/// qu'un utilisateur peut lire sans avoir l'application.
///
/// ── Pourquoi plus la webview interne ──────────────────────────────────────
///
/// Elle l'avait d'abord emporté, pour ne pas faire sortir de l'application au
/// moment du paiement. Mais les pages du site portent leur propre en-tête :
/// empilé sous la barre de l'application, cela faisait deux en-têtes, et
/// surtout une sortie. « Retour à l'accueil » chargeait la page commerciale
/// *dans* l'application, dont l'appel à l'action est « Télécharger l'app » —
/// l'application déjà en cours d'exécution.
///
/// La contrepartie assumée : sur le paywall, le lecteur quitte l'application
/// pour lire les conditions. C'est le prix d'une page qui s'affiche chez elle,
/// avec un retour que tout le monde sait faire.
///
/// « Jeu responsable » fait exception, et c'est dit : le site n'a pas cette
/// page, et ces ressources doivent rester atteignables hors ligne.
void main() {
  String lire(String chemin) {
    final f = File(chemin);
    expect(f.existsSync(), isTrue, reason: '$chemin introuvable');
    return f.readAsStringSync();
  }

  const liens = 'lib/core/config/pages_legales.dart';
  const routeur = 'lib/core/router/app_router.dart';

  test('les adresses construites sont celles que le site sert', () {
    expect(PagesLegales.cgu(estStore: true), 'https://pronowin.space/cgu');
    expect(PagesLegales.cgu(estStore: false),
        'https://pronowin.space/cgu?canal=direct');
    expect(PagesLegales.confidentialite,
        'https://pronowin.space/confidentialite');
    expect(PagesLegales.mentionsLegales,
        'https://pronowin.space/mentions-legales');

    final serveur = lire('../website/server.js');
    for (final chemin in ['/cgu', '/confidentialite', '/mentions-legales']) {
      expect(serveur, contains("app.get('$chemin'"),
          reason: 'le site ne sert pas $chemin : le lien mènerait à un 404, '
                  'dans une webview, hors de toute surveillance');
    }
  });

  test('l\'ouverture passe par le navigateur du système', () {
    final source = lire(liens);
    expect(source, contains('LaunchMode.externalApplication'),
        reason: 'les pages légales doivent s\'ouvrir hors de l\'application');
    expect(source, isNot(contains("context.push('/navigateur'")),
        reason: 'la webview interne empilait son en-tête sous celui du site, '
                'dont le « Retour à l\'accueil » ramenait la page commerciale '
                'dans l\'application');
  });

  test('l\'ouverture ne se fie pas à canLaunchUrl', () {
    // Il répond faux sur Android dès qu'aucune requête de visibilité de paquet
    // ne couvre le schéma, alors même que l'ouverture aurait réussi. S'en
    // servir comme garde transformerait un lien qui marche en lien mort — la
    // leçon est déjà écrite dans `BookmakerAffiliation.ouvrir`.
    //
    // Seules les lignes actives comptent : le commentaire du fichier *doit*
    // nommer `canLaunchUrl` pour expliquer pourquoi il est écarté.
    final actif = lire(liens)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(actif, isNot(contains('canLaunchUrl')));
  });

  test('aucun lien légal ne contourne PagesLegales', () {
    // `/navigateur` sert aussi aux articles d'actualité : on ne l'interdit pas
    // ailleurs. Ce qu'on interdit, c'est qu'une adresse légale soit écrite à la
    // main dans un écran — ce qui ferait une seconde source pour la même URL,
    // et la ferait diverger le jour où le site change de chemin.
    final fautifs = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll(r'\', '/').endsWith(liens)) continue;
      final source = f.readAsStringSync();
      for (final chemin in ['/cgu', '/confidentialite', '/mentions-legales']) {
        if (source.contains("'\$chemin'") || source.contains('siteUrl}$chemin')) {
          fautifs.add('${f.path} écrit $chemin à la main');
        }
      }
    }
    expect(fautifs, isEmpty);
  });

  test('les copies embarquées ne sont plus routées', () {
    final source = lire(routeur);
    for (final chemin in ['/parametres/cgu', '/parametres/confidentialite']) {
      expect(source, isNot(contains("path: '$chemin'")),
          reason: '$chemin rouvrirait la copie embarquée : deux textes pour un '
                  'seul document, et deux endroits à tenir à jour');
    }

    // Contrepartie : sans elle, supprimer toute la section légale du routeur
    // passerait ce contrôle sans que rien ne bronche.
    expect(source, contains("path: '/parametres/jeu-responsable'"),
        reason: 'le site n\'a pas cette page, et ces ressources doivent rester '
                'atteignables hors ligne');
    expect(source, contains("path: '/navigateur'"));
  });

  test('plus aucun écran ne pousse les anciennes routes', () {
    final fautifs = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final source = f.readAsStringSync();
      for (final chemin in ['/parametres/cgu', '/parametres/confidentialite']) {
        if (source.contains("push('$chemin')")) {
          fautifs.add('${f.path} ouvre $chemin, qui n\'existe plus');
        }
      }
    }
    expect(fautifs, isEmpty);
  });

  test('le texte reste la source de la page publiée', () {
    // Les routes ont disparu, pas le texte. `sectionsLegales` alimente
    // toujours `website/content/cgu.json` par `tool/exporter_cgu.dart`, et
    // `cgu_site_coherent_test.dart` compare les deux. Supprimer la fonction
    // laisserait la page du site sans source.
    expect(
      lire('lib/features/parametres/presentation/pages/legal_page.dart'),
      contains('List<LegalSection> sectionsLegales('),
      reason: 'sectionsLegales alimente la page publiée sur le site',
    );
    expect(File('tool/exporter_cgu.dart').existsSync(), isTrue);
  });
}
