import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';

/// Le paywall ne doit pas dépendre de qui l'a ouvert.
///
/// ── Le défaut ─────────────────────────────────────────────────────────────
///
/// Tarifs, code promo et moyens de paiement venaient de `subData`, une carte
/// passée en `extra` au moment de pousser la route. Cinq chemins mènent à cet
/// écran ; **un seul** la passait.
///
/// Ouvert depuis l'onglet Performance, depuis la feuille de blocage Premium,
/// ou au retour de « compléter le profil », `subData` valait `null`. L'écran
/// affichait alors :
///
///   - « Offre momentanément indisponible — Le code partenaire nous manque » ;
///   - « Paiement Direct · Momentanément indisponible » ;
///   - et « $10 / $90 », qui ne sont pas des tarifs mais les replis compilés
///     `?? 10` et `?? 90` des quatre lignes lisant `widget.subData` en direct.
///
/// ── Pourquoi personne ne l'a vu ───────────────────────────────────────────
///
/// Ces deux messages d'indisponibilité existent exprès. Ils disent l'absence
/// plutôt que d'inventer un code d'affiliation qui ne crédite personne — c'est
/// une protection, et elle est juste. Un écran entièrement vide passait donc
/// pour un écran honnête, alors que `PROMO_CODE = PRONOWIN2026` était en base
/// et publié par l'API.
///
/// Le panneau d'administration, lui, affichait « Code en service :
/// PRONOWIN2026 ». Les deux écrans se contredisaient, et c'est l'application
/// qui avait tort.
///
/// ── Ce que ce banc tient ──────────────────────────────────────────────────
///
/// La page est montée **sans** `subData`, exactement comme le fait
/// `performance_page.dart`. Ce que le serveur publie doit apparaître quand
/// même.
void main() {
  /// Ce que publie `/subscriptions/current`. Les valeurs sont choisies pour ne
  /// ressembler à aucun repli compilé : si l'une d'elles s'affiche, elle vient
  /// forcément du serveur.
  const duServeur = <String, dynamic>{
    'plan': 'free',
    'days_left': 0,
    'promo_code': 'CODESERVEUR77',
    'premium_price_monthly_usd': 42,
    'premium_price_annual_usd': 411,
    'betting_platforms': ['1xbet', 'melbet', 'betwinner'],
    'code_offer_days': 30,
    'payment_methods': <Map<String, dynamic>>[],
  };

  Future<void> monter(
    WidgetTester tester, {
    required Map<String, dynamic> publie,
    Map<String, dynamic>? parLaRoute,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => publie),
        // Canal direct : évite l'achat intégré, qui exige une boutique.
        isStoreBuildProvider.overrideWithValue(false),
        // Le notifier réclame un Dio ; un Dio nu suffit, contrairement à
        // `DioClient` qui construit l'intercepteur Firebase.
        submitProofProvider
            .overrideWith((ref) => SubmitProofNotifier(Dio())),
      ],
      child: MaterialApp(
        // Sans `subData` : c'est tout l'objet du banc.
        home: ActiverPremiumPage(subData: parLaRoute),
      ),
    ));
    await tester.pump();
    // `initState` pose un filet de sécurité « profil incomplet » qui lit
    // `authProvider` ; celui-ci construit des dépendances Firebase, absentes
    // hors application. L'exception survient dans un rappel post-frame, après
    // que l'arbre est construit : elle ne change rien à ce qui est affiché, et
    // ce banc ne porte pas sur elle.
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();

    // Le paywall porte une animation qui se répète : `pumpAndSettle`
    // n'aboutit jamais, et laisser l'arbre en place fait échouer le banc sur
    // « A Timer is still pending » plutôt que sur ce qu'il mesure. Démonter
    // libère les contrôleurs, donc les minuteurs.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  testWidgets('ouvert sans données de route, il affiche le tarif du serveur',
      (tester) async {
    await monter(tester, publie: duServeur);

    expect(find.textContaining('42'), findsWidgets,
        reason: 'le tarif publié par le serveur ne s\'affiche pas');
  });

  testWidgets('et surtout pas le repli compilé', (tester) async {
    // `?? 10` était la valeur réellement vue à l'écran quand `subData`
    // manquait. Elle ne doit plus pouvoir apparaître alors que le serveur
    // publie autre chose.
    await monter(tester, publie: duServeur);

    expect(find.text('\$10'), findsNothing,
        reason: 'le prix affiché vient encore du repli écrit dans le code');
  });

  testWidgets('aucun code d\'affiliation n\'est compilé dans l\'écran',
      (tester) async {
    // Le code partenaire lui-même ne s'affiche pas sur le paywall : la carte
    // « Avec Code Promo » n'annonce que l'offre, et la réponse de la FAQ qui
    // le cite n'est construite qu'une fois la question dépliée. Ce que ce
    // banc peut tenir ici, c'est l'autre moitié de la règle : quand le
    // serveur n'en publie aucun, aucun ne doit apparaître.
    //
    // Le fait que le code *publié* arrive bien à l'écran est prouvé par les
    // tarifs ci-dessus : il emprunte exactement le même chemin
    // (`_donnees` → `TarifsPremium`), et c'est ce chemin qui était rompu.
    // La règle « ne jamais lire `widget.subData` en direct » est tenue par
    // `premium_sans_valeurs_en_dur_test.dart`, champ par champ.
    await monter(tester, publie: {...duServeur, 'promo_code': ''});

    expect(find.textContaining('PRONOWIN'), findsNothing,
        reason: 'un code d\'affiliation écrit en dur s\'est glissé dans '
            'l\'écran : il ne créditerait personne');
  });

  testWidgets('les données de route restent acceptées quand elles sont là',
      (tester) async {
    // Elles évitent un clignotement au premier affichage ; le serveur reprend
    // la main dès qu'il a répondu.
    await monter(tester,
        publie: duServeur,
        parLaRoute: {...duServeur, 'premium_price_monthly_usd': 99});

    expect(find.textContaining('42'), findsWidgets,
        reason: 'la réponse du serveur doit primer sur la carte de route');
  });
}
