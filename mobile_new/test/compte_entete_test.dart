import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/compte/presentation/pages/compte_page.dart';
import 'package:pronowin/features/compte/presentation/providers/compte_provider.dart';
import 'package:pronowin/features/parrainage/presentation/providers/referral_provider.dart';

import 'aides/banc_ecran.dart';

/// L'en-tête de la page Compte : pastilles visibles, initiale cohérente.
///
/// Vu sur iPhone (5 octobre 2026) : « PREMIUM » et « 1 j restants » à moitié
/// cachés sous les onglets, et un avatar « B » ici quand l'Accueil affichait
/// « P » pour la même personne.
void main() {
  setUpAll(preparerBanc);

  final surcharges = [
    profileProvider.overrideWith((ref) async => {
          'pseudo': 'Parieur_7AGY8', 'first_name': 'boss', 'last_name': 'gand',
          'subscription_plan': 'premium', 'referral_code': '302602', 'referral_earnings': 0,
        }),
    userStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
    bankrollProvider.overrideWith((ref) async => null),
    bankrollStatsProvider.overrideWith((ref) async => null),
    currentSubscriptionProvider.overrideWith((ref) async => <String, dynamic>{'plan': 'premium', 'days_left': 1}),
    referralStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
  ];

  for (final echelle in [1.0, 1.8]) {
    testWidgets('les pastilles restent au-dessus des onglets · texte ${(echelle * 100).round()} %', (t) async {
      late Rect pastille, onglets;
      var initiale = '';
      final r = await mesurerEcran(t, ecran: const ComptePage(), theme: AppTheme.light,
          echelle: echelle, largeur: 390, surcharges: surcharges, defilements: 0,
          verifier: () {
            pastille = t.getRect(find.text('1 j restant'));
            onglets  = t.getRect(find.byKey(const Key('onglets-compte')));
            initiale = (t.widget<Text>(find.text('B').first)).data ?? '';
          });
      expect(r.debordements, isEmpty);
      expect(pastille.bottom, lessThanOrEqualTo(onglets.top),
          reason: 'la pastille passe sous les onglets');
      expect(initiale, 'B', reason: 'l\'initiale est celle du prénom, comme « Bonjour, boss »');
    });
  }
}
