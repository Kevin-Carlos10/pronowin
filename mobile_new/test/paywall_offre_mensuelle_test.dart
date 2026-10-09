import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';

/// L'offre « code promo » ne s'affiche pas en face d'une formule annuelle.
///
/// ── Ce qui était montré ───────────────────────────────────────────────────
///
/// Le paywall proposait, côte à côte :
///
///   « Annuel · 2 mois offerts » — 90 $/an
///   « Avec Code Promo · 1 mois offert » — 0 $
///
/// Deux promesses qui ne parlent pas de la même chose, et dont la moins chère
/// ne délivre pas ce que la formule annonce : l'offre porte sur le **premier
/// mois**, jamais sur l'année.
///
/// ── Le piège de la correction ─────────────────────────────────────────────
///
/// Masquer la carte sans désélectionner la méthode aurait laissé `_method` sur
/// « code » : aucune option n'aurait paru choisie, le bouton aurait annoncé
/// « Continuer avec le code (annuel) », et il aurait ouvert le parcours code
/// promo pour une formule annuelle.
///
/// Ce libellé existait déjà dans le code — la combinaison avait donc été
/// anticipée, mais jamais empêchée.
///
/// La méthode est désormais **dérivée** de la durée, pas seulement remise à
/// zéro : l'onglet « Code Promo » du formulaire repose `_method` à « code », et
/// revenir en arrière ramenait exactement dans cet état.
void main() {
  _regle();
  const publie = <String, dynamic>{
    'plan': 'free', 'days_left': 0,
    'promo_code': 'CODE77',
    'premium_price_monthly_usd': 10,
    'premium_price_annual_usd': 90,
    'betting_platforms': ['1xbet'],
    'code_offer_days': 30,
    'payment_methods': <Map<String, dynamic>>[],
  };

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSubscriptionProvider.overrideWith((ref) async => publie),
        isStoreBuildProvider.overrideWithValue(false),
        submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
      ],
      child: const MaterialApp(home: ActiverPremiumPage()),
    ));
    await tester.pump();
    // `initState` pose un filet « profil incomplet » qui lit `authProvider`,
    // lequel construit des dépendances Firebase absentes hors application.
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();

    // Le paywall porte une animation qui se répète : démonter libère les
    // minuteurs, sinon le banc échoue sur « A Timer is still pending ».
    addTearDown(() async {
      // Les entrées en scène de `flutter_animate` posent des minuteurs
      // différés ; les laisser en vol ferait échouer le banc sur « A Timer is
      // still pending » plutôt que sur ce qu'il mesure. On les laisse arriver,
      // puis on démonte pour libérer les contrôleurs qui se répètent.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  final carteCode = find.text('Avec Code Promo');

  testWidgets('sur le mensuel, elle est proposée', (tester) async {
    // Le contre-test : la masquer partout supprimerait l'offre au lieu de la
    // restreindre.
    await monter(tester);
    expect(carteCode, findsOneWidget);
  });

  testWidgets('sur l\'annuel, elle disparaît', (tester) async {
    await monter(tester);
    await tester.tap(find.textContaining('Annuel'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(carteCode, findsNothing,
        reason: '« 1 mois offert » en face de « 2 mois offerts » promet moins '
            "que la formule, alors qu'elle ne coûte rien");
  });

  testWidgets('et le bouton ne propose plus le code', (tester) async {
    // Le cœur du défaut : une carte masquée mais toujours sélectionnée.
    await monter(tester);
    await tester.tap(carteCode);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.textContaining('Annuel'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Continuer avec le code'), findsNothing,
        reason: 'la méthode est restée sur « code » alors que sa carte '
            'a disparu : le bouton emmène vers un parcours que l\'écran '
            'ne propose plus');
  });

  // Le chemin « annuel → formulaire → onglet Code Promo → retour » n'est pas
  // exercé ici : l'écran du formulaire laisse un minuteur d'animation que le
  // banc rejette avant d'avoir pu mesurer quoi que ce soit. La règle qu'il
  // aurait vérifiée est testée directement, plus bas, sur `methodeProposee`.

  testWidgets('revenir au mensuel la propose de nouveau', (tester) async {
    await monter(tester);
    await tester.tap(find.textContaining('Annuel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Mensuel'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(carteCode, findsOneWidget);
  });
}

/// La règle, isolée de l'écran.
///
/// C'est elle qui ferme le chemin que les tests d'interface ci-dessus ne
/// parcourent pas : revenir au paywall depuis l'onglet « Code Promo » du
/// formulaire, avec une durée restée annuelle. Aucune remise à zéro n'a lieu
/// sur ce trajet — seule une valeur dérivée tient.
void _regle() {
  group('la méthode proposée se déduit de la durée', () {
    test('sur l\'annuel, c\'est toujours le paiement direct', () {
      expect(methodeProposee(duree: 'annuel', choisie: 'code'), 'direct');
      expect(methodeProposee(duree: 'annuel', choisie: 'direct'), 'direct');
    });

    test('sur le mensuel, le choix de l\'utilisateur est respecté', () {
      // Le contre-test : forcer « direct » partout supprimerait l'offre au
      // lieu de la restreindre.
      expect(methodeProposee(duree: 'mensuel', choisie: 'code'), 'code');
      expect(methodeProposee(duree: 'mensuel', choisie: 'direct'), 'direct');
    });
  });
}
