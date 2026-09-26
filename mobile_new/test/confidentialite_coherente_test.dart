import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'application et le site décrivent la même collecte de données.
///
/// La politique de confidentialité existe à deux endroits : dans
/// l'application (`legal_page.dart`) et sur le site
/// (`website/views/confidentialite.ejs`, l'URL déclarée à Google). Deux
/// textes, deux dates de révision indépendantes, pour un seul document
/// juridique.
///
/// Ils avaient déjà divergé. Le site, corrigé pour coller à la réalité,
/// détaillait cinq catégories ; l'application en annonçait trois. Y manquaient
/// l'empreinte du mot de passe, le prénom et le nom, le pays, la photo de
/// profil, les votes et commentaires, l'état de l'abonnement, et les rapports
/// de plantage et mesures de performance — alors que Crashlytics et
/// Performance tournent depuis le premier jour.
///
/// Le sens de l'écart compte. **Sur-déclarer** fait peur pour rien et
/// contredit le formulaire de sûreté des données. **Sous-déclarer** — le cas
/// ici — promet à l'utilisateur moins que ce qui est réellement collecté. Les
/// deux sont des défauts ; ce contrôle refuse les deux, dans les deux sens.
///
/// Il ne compare pas la rédaction : les deux textes n'ont pas le même ton ni
/// le même public. Il compare les **faits déclarés**, catégorie par catégorie.
void main() {
  const cheminSite = '../website/views/confidentialite.ejs';
  const cheminApp  = 'lib/features/parametres/presentation/pages/legal_page.dart';

  late String site;
  late String app;

  setUpAll(() {
    final f = File(cheminSite);
    // Pas de `skip` si le site manque : un contrôle qui s'efface quand il ne
    // peut pas travailler finit par ne plus rien garder. Les deux vivent dans
    // le même dépôt.
    expect(f.existsSync(), isTrue,
      reason: '$cheminSite introuvable — ce contrôle compare l\'application au '
              'site, il ne peut rien affirmer sans les deux');
    site = f.readAsStringSync().toLowerCase();
    app  = File(cheminApp).readAsStringSync().toLowerCase();
  });

  /// Ce que chaque texte doit déclarer, ou taire, de la même façon.
  ///
  /// La clé est l'intitulé lisible ; les valeurs sont les formulations
  /// acceptées de part et d'autre — les deux textes ne nomment pas toujours
  /// une même donnée avec les mêmes mots.
  const categories = <String, List<String>>{
    'empreinte de mot de passe' : ['mot de passe'],
    'prénom et nom'             : ['prénom'],
    'pays'                      : ['pays'],
    'date de naissance'         : ['date de naissance'],
    'photo de profil'           : ['photo de profil'],
    'pseudonyme'                : ['pseudo'],
    'favoris'                   : ['favoris'],
    'bankroll'                  : ['bankroll'],
    'parrainage'                : ['parrainage'],
    'votes et commentaires'     : ['commentaires'],
    'jeton de notification'     : ['jeton de notification', 'token de notification'],
    'rapports de plantage'      : ['plantage'],
    'mesures de performance'    : ['performance'],
    'état de l\'abonnement'     : ['abonnement'],
  };

  bool declare(String texte, List<String> formulations) =>
      formulations.any(texte.contains);

  test('les deux textes déclarent les mêmes catégories de données', () {
    final ecarts = <String>[];

    categories.forEach((intitule, formulations) {
      final dansSite = declare(site, formulations);
      final dansApp  = declare(app,  formulations);
      if (dansSite && !dansApp) {
        ecarts.add('« $intitule » : déclaré sur le site, absent de '
                   'l\'application — l\'application sous-déclare');
      } else if (dansApp && !dansSite) {
        ecarts.add('« $intitule » : déclaré dans l\'application, absent du '
                   'site — le site sous-déclare');
      }
    });

    expect(ecarts, isEmpty,
      reason: 'un seul document juridique, deux textes qui ne disent pas la '
              'même chose :\n  ${ecarts.join("\n  ")}');
  });

  test('les deux promettent de ne pas collecter la position et les contacts', () {
    // Une promesse d'abstention est aussi une déclaration. Si l'une des deux
    // pages la retire, c'est soit que la collecte a changé — et l'autre page
    // ment — soit qu'on a perdu une garantie sans le vouloir.
    for (final entry in {'site': site, 'application': app}.entries) {
      expect(entry.value, contains('gps'),
        reason: 'la ${entry.key} ne dit plus que la position n\'est pas collectée');
      expect(entry.value, contains('contacts'),
        reason: 'la ${entry.key} ne dit plus que les contacts ne sont pas collectés');
    }
  });

  test('l\'adresse de contact de l\'application est celle du site', () {
    // Le point de contact pour exercer ses droits. Les deux ne l'obtiennent
    // pas de la même façon : le site la lit dans sa configuration
    // (`site.contactEmail`), l'application l'écrit en dur — quatre fois.
    //
    // Elles coïncident aujourd'hui parce que `CONTACT_EMAIL` n'est pas défini
    // en production et que le site retombe sur son défaut. C'est une
    // coïncidence, pas une garantie : le jour où cette variable est renseignée,
    // le site change d'adresse et l'application continue d'afficher l'ancienne
    // jusqu'à la prochaine version.
    //
    // Ce contrôle verrouille au moins les deux valeurs présentes dans le dépôt.
    // Si la variable d'environnement est un jour utilisée, il faudra faire lire
    // l'adresse à l'application depuis l'API plutôt que de la figer.
    final serveur = File('../website/server.js');
    expect(serveur.existsSync(), isTrue, reason: 'website/server.js introuvable');

    final defaut = RegExp(r"contactEmail:\s*process\.env\.CONTACT_EMAIL\s*\|\|\s*'([^']+)'")
        .firstMatch(serveur.readAsStringSync())?.group(1);

    expect(defaut, isNotNull,
      reason: 'le site ne lit plus son adresse de contact depuis la '
              'configuration — revoir ce contrôle avant de le supprimer');

    expect(app, contains(defaut!.toLowerCase()),
      reason: 'l\'application affiche une adresse de contact différente de '
              'celle du site ($defaut) : les demandes d\'exercice de droits '
              'partiront à deux endroits');

    // Et le site doit continuer de la prendre dans sa configuration plutôt que
    // de la figer dans la page.
    expect(site, contains('site.contactemail'),
      reason: 'le site a fige son adresse dans la page : elle ne suivra plus '
              'la configuration');
  });
}
