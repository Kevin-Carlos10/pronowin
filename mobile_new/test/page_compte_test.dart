import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/compte/presentation/pages/compte_page.dart';
import 'package:pronowin/features/compte/presentation/providers/compte_provider.dart';
import 'package:pronowin/features/parrainage/presentation/providers/referral_provider.dart';
import 'package:pronowin/shared/utils/age.dart';
import 'package:pronowin/shared/utils/bilan_paris.dart';

/// L'écran du compte, monté pour de vrai.
///
/// Aucun banc ne le montait : `BilanParis` était éprouvé, la page ne l'était
/// pas. Trois des défauts corrigés ici étaient invisibles à la relecture et
/// n'auraient été vus que par quelqu'un regardant l'écran avec les bonnes
/// données — un email long, un compte sans téléphone, quatre paris tranchés.
void main() {
  // ── L'âge ─────────────────────────────────────────────────────────────────
  //
  // Le calcul divisait les jours par 365,25. Sur trente dates éprouvées, vingt
  // donnaient un an de moins **le jour de l'anniversaire** — le seul jour de
  // l'année où quelqu'un regarde cette ligne.
  //
  // Le même défaut avait déjà été trouvé et corrigé côté serveur
  // (`backend/src/utils/age.ts`), où il décidait de la majorité. La règle était
  // écrite, corrigée et éprouvée d'un seul côté.
  group('âge révolu', () {
    int ancienCalcul(DateTime n, DateTime m) =>
        (m.difference(n).inDays / 365.25).floor();

    test('le jour de l\'anniversaire, l\'âge est atteint', () {
      // Le cas qui échouait, et qui échoue encore avec l'ancien calcul.
      final ne = DateTime(2005, 3, 1);
      final jourJ = DateTime(2026, 3, 1);

      expect(ageRevolu(ne, jourJ), 21);
      expect(ancienCalcul(ne, jourJ), 20,
          reason: 'la contrepartie : sans écart entre les deux calculs, ce '
                  'banc ne prouverait rien');
    });

    test('la veille, il ne l\'est pas', () {
      expect(ageRevolu(DateTime(2005, 3, 1), DateTime(2026, 2, 28)), 20);
    });

    test('un 29 février ne fait pas d\'exception', () {
      // Né un 29 février : l'anniversaire tombe le 1er mars les années non
      // bissextiles. Le 28 février, l'âge n'est pas encore atteint.
      expect(ageRevolu(DateTime(2004, 2, 29), DateTime(2026, 2, 28)), 21);
      expect(ageRevolu(DateTime(2004, 2, 29), DateTime(2026, 3, 1)), 22);
    });

    test('aucune date ne donne un âge faux le jour même', () {
      // Le balayage qui a révélé le défaut : vingt cas sur trente.
      for (var annee = 1990; annee <= 2008; annee++) {
        for (final mois in [1, 2, 3, 5, 6, 8, 9, 11, 12]) {
          final ne = DateTime(annee, mois, 1);
          final jourJ = DateTime(annee + 18, mois, 1);
          expect(ageRevolu(ne, jourJ), 18,
              reason: 'né le 01/$mois/$annee : le jour de ses 18 ans');
        }
      }
    });
  });

  test('aucun écran ne recalcule un âge par division', () {
    // La première version de ce contrôle ne regardait que l'écran du compte.
    // Il y en avait une **troisième** copie, dans l'écran de modification du
    // profil — sous la date de naissance, en vert, précisément là où la ligne
    // sert à confirmer qu'on est majeur. Elle est restée intacte pendant que
    // je corrigeais l'autre.
    //
    // Un contrôle attaché à un fichier ne protège que ce fichier. Celui-ci
    // balaie tout `lib/`, et c'est ce qu'il aurait fallu dès le départ.
    final fautifs = <String>[];
    var emplois = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final source = f.readAsStringSync();
      // `age.dart` cite la formule qu'il remplace, dans sa documentation :
      // c'est le seul fichier où ces cinq caractères sont attendus.
      final estLeCalculPartage = f.path.endsWith('age.dart');
      if (!estLeCalculPartage && source.contains('365.25')) fautifs.add(f.path);
      if (source.contains('ageRevolu(')) emplois++;
    }

    expect(fautifs, isEmpty,
        reason: 'la division approximative est revenue : elle se trompe d\'un '
                'an le jour de l\'anniversaire');
    // Contrepartie : un dépôt où plus personne n'appelle le calcul partagé
    // passerait le contrôle ci-dessus sans rien garder.
    expect(emplois, greaterThan(1),
        reason: 'le calcul calendaire doit être celui qu\'on emploie, '
                'et pas seulement celui qui existe');
  });

  test('l\'onglet Aperçu ne double plus la barre du bas', () {
    // Sept liens, dont trois menaient là où un seul appui menait déjà :
    // « Pronostics » vers l'onglet Pronos, « Tutoriels » vers l'onglet
    // Tutoriels, « Programme parrainage » vers l'onglet juste au-dessus. Et
    // `/historique` était atteignable **trois fois** sur le même écran.
    //
    // Le fichier portait déjà la règle, écrite pour la bande « Actions
    // rapides » qui avait été retirée pour cette raison : « ses quatre tuiles
    // dupliquaient toutes un accès déjà présent à l'écran ». Elle n'avait pas
    // été appliquée aux deux listes qui l'ont remplacée.
    final source = File(
      'lib/features/compte/presentation/pages/compte_page.dart',
    ).readAsStringSync();
    final onglet = source.substring(
      source.indexOf('class _ApercuTab'),
      source.indexOf('// ONGLET ABONNEMENT'),
    );

    for (final ailleurs in ['/pronostics', '/tutoriels', '/parrainage']) {
      expect(onglet.contains("('$ailleurs')"), isFalse,
          reason: '$ailleurs est déjà à un appui : deux onglets de la barre '
                  'du bas, et le troisième onglet de cette page même');
    }

    final versHistorique =
        RegExp(r"push\('/historique'\)").allMatches(onglet).length;
    expect(versHistorique, 1,
        reason: 'il y avait trois chemins vers la même page sur cet écran : '
                'la carte entière, son lien « Historique », et une ligne '
                '« Historique des résultats »');
  });

  test('la fiche en lecture seule a laissé place à un accès en écriture', () {
    // Sept lignes que l'utilisateur connaît par cœur, un tiers de l'écran, et
    // aucune modifiable depuis là : le seul accès à l'édition était le crayon
    // de la photo, dont le libellé d'accessibilité annonce « Modifier la photo
    // de profil ».
    final source = File(
      'lib/features/compte/presentation/pages/compte_page.dart',
    ).readAsStringSync();
    expect(source, contains("label: 'Mes informations'"));
    expect(source, contains("push('/compte/edit')"));
    expect(source, isNot(contains("_InfoRow(label: 'Téléphone'")),
        reason: 'la fiche en lecture seule est revenue');
  });

  // ── Ce qui manque avant le taux ──────────────────────────────────────────
  group('avant le taux de réussite', () {
    BilanParis bilan(int gagnes, int perdus, {int suivis = 0}) => BilanParis(
          suivis: suivis == 0 ? gagnes + perdus : suivis,
          gagnes: gagnes, perdus: perdus, tauxBrut: 0, serie: 0);

    test('compte ce qui manque', () {
      expect(bilan(3, 1).avantLeTaux, 1);
      expect(bilan(1, 0).avantLeTaux, 4);
    });

    test('ne descend pas sous zéro une fois le seuil franchi', () {
      expect(bilan(6, 2).avantLeTaux, 0);
      expect(bilan(6, 2).echantillonSuffisant, isTrue);
    });
  });

  // ── Le rafraîchissement couvre ce que l'écran affiche ────────────────────
  //
  // Le geste n'invalidait que le profil, l'abonnement et le parrainage — rien
  // de ce que l'onglet Aperçu montre. Le solde et les statistiques de paris,
  // les deux cartes du haut, ne bougeaient pas : le geste tournait, l'écran
  // restait identique.
  //
  // Ce contrôle ne fige pas une liste : il compare ce que la page **lit** à ce
  // que le rafraîchissement **relit**. Ajouter demain un provider à l'écran
  // sans l'ajouter au geste le fera échouer.
  test('tout ce que la page lit est relu au rafraîchissement', () {
    final source = File(
      'lib/features/compte/presentation/pages/compte_page.dart',
    ).readAsStringSync();

    final fonction = RegExp(
      r'void rafraichirDonneesCompte\(WidgetRef ref\) \{([\s\S]*?)\n\}',
    ).firstMatch(source);
    expect(fonction, isNotNull,
        reason: 'rafraichirDonneesCompte introuvable');

    final relus = RegExp(r'ref\.invalidate\((\w+)\)')
        .allMatches(fonction!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(relus, isNotEmpty);

    // `isStoreBuildProvider` ne lit rien : il rend une constante de
    // compilation, et l'invalider n'aurait aucun effet.
    const sansObjet = {'isStoreBuildProvider'};

    final lus = RegExp(r'ref\.watch\((\w+Provider)')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet()
        .difference(sansObjet);

    expect(lus.difference(relus), isEmpty,
        reason: 'ces providers sont affichés par la page mais pas relus par le '
                'geste de rafraîchissement : ${lus.difference(relus)}');

    // Le geste et la déconnexion partagent la même liste. Deux listes écrites
    // à la main divergeaient : celle du haut oubliait les statistiques et la
    // bankroll, celle du bas l'abonnement et le parrainage.
    expect('rafraichirDonneesCompte(ref)'.allMatches(source).length,
        greaterThanOrEqualTo(0));
    expect(RegExp(r'rafraichirDonneesCompte\(ref\)').allMatches(source).length,
        2,
        reason: 'le rafraîchissement et la déconnexion doivent tous deux '
                'passer par la liste unique');
  });

  // ── La page montée ────────────────────────────────────────────────────────
  group('fiche d\'informations', () {
    Widget sousTest({
      String email = 'a@b.co',
      String phone = '+22670000000',
      Map<String, dynamic>? stats,
    }) =>
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) async => {
                  'pseudo': 'Parieur_7AGY8',
                  'phone_number': phone,
                  'email': email,
                  'country_code': '',
                  'first_name': 'boss',
                  'last_name': 'gand',
                  'birth_date': '2006-01-21T00:00:00.000Z',
                  'subscription_plan': 'free',
                  'created_at': '2026-08-01T00:00:00.000Z',
                  'referral_code': 'ABC123',
                  'referral_earnings': 0,
                }),
            userStatsProvider.overrideWith((ref) async =>
                stats ??
                {
                  'pronostics_suivis': 4,
                  'paris_gagnes': 3,
                  'paris_perdus': 1,
                  'taux_reussite': 75,
                  'serie_gagnante': 2,
                }),
            // `null` : aucune bankroll configurée. La carte devient une
            // invitation, ce qui suffit ici — c'est la fiche qu'on éprouve.
            bankrollProvider.overrideWith((ref) async => null),
            currentSubscriptionProvider
                .overrideWith((ref) async => <String, dynamic>{}),
            referralStatsProvider
                .overrideWith((ref) async => <String, dynamic>{}),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ComptePage(),
          ),
        );

    Future<void> monter(WidgetTester tester, Widget w) async {
      // Haute volontairement : la fiche d'informations est loin sous la
      // ligne de flottaison, et une `ListView` ne construit que ce qu'elle
      // affiche. Faire defiler la marche aussi, mais laisse derriere elle la
      // simulation balistique du defilement — un minuteur encore actif a la
      // fin du test, que le harnais signale comme une fuite. La largeur, elle,
      // reste celle d'un telephone etroit : c'est elle qui decide des
      // debordements.
      tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
      // Pas de `pumpAndSettle` : la pastille Premium anime en boucle.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('un email long ne déborde pas', (tester) async {
      // `Spacer` + `Text` nu : une adresse un peu longue peignait les rayures
      // de débordement en travers de la fiche, sur un écran de 360 px, à
      // taille de texte normale.
      await monter(tester,
          sousTest(email: 'prenom.nom.tres.long@messagerie-exemple.com'));

      expect(tester.takeException(), isNull,
          reason: 'la valeur doit pouvoir passer à la ligne');
    });

    // Le contrôle « une donnée absente est nommée » a été retiré avec son
    // sujet : la fiche d'informations n'est plus sur cet écran, et l'écran de
    // modification qui la remplace présente des champs de saisie — un champ
    // vide y est correct, il attend une saisie. La règle n'a plus de sens ici,
    // et un contrôle sans sujet finit par être contourné plutôt que compris.

    testWidgets('le tiret de réussite dit ce qui manque', (tester) async {
      // Quatre paris tranchés : le pourcentage est retenu, à juste titre. Mais
      // la branche voisine nomme son état et celle-ci laissait un tiret nu.
      await monter(tester, sousTest());

      expect(find.text('—'), findsWidgets);
      expect(find.text('Taux de réussite dès le prochain pari tranché'),
          findsOneWidget);
    });

    testWidgets('au-dessus du seuil, aucune explication ne traîne',
        (tester) async {
      // Contrepartie : une explication affichée en permanence serait un
      // reproche permanent.
      await monter(tester, sousTest(stats: {
        'pronostics_suivis': 8,
        'paris_gagnes': 6,
        'paris_perdus': 2,
        'taux_reussite': 75,
        'serie_gagnante': 2,
      }));

      expect(find.textContaining('Taux de réussite dès'), findsNothing);
    });
  });
}
