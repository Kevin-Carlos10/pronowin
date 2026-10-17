import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/pages/activer_premium_page.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/bankroll/presentation/pages/bankroll_page.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/compte/presentation/pages/compte_page.dart';
import 'package:pronowin/features/compte/presentation/providers/compte_provider.dart';
import 'package:pronowin/features/parrainage/presentation/providers/referral_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/pages/pronostics_page.dart';
import 'package:pronowin/shared/utils/resume_paris.dart';

import 'aides/banc_ecran.dart';

/// Les écrans principaux, entiers, à 360 px et texte agrandi à 180 %.
///
/// L'accueil a son propre banc (`accueil_texte_agrandi_test.dart`), qui y a
/// trouvé six débordements. Les autres écrans n'étaient jamais assemblés :
/// seuls leurs composants l'étaient, isolément. Le même banc les monte ici,
/// dans les deux thèmes, avec des noms d'équipe et des montants longs.
void main() {
  setUpAll(preparerBanc);

  final ecrans = <String, (Widget, List<Override>)>{
    'Pronostics': (const PronosticsPage(), const []),
    'Détail du match': (const MatchDetailPage(matchId: '2'), const []),
    'Bankroll': (const BankrollPage(), [bankrollProvider.overrideWith((ref) async => _bankroll())]),
    'Compte': (const ComptePage(), _compte()),
    'Paywall': (const ActiverPremiumPage(), _paywall()),
  };

  for (final MapEntry(key: nom, value: (ecran, surcharges)) in ecrans.entries) {
    for (final (nomTheme, theme) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
      for (final echelle in [1.0, 1.8]) {
        testWidgets('$nom · $nomTheme · texte ${(echelle * 100).round()} % · 360 px', (tester) async {
          final r = await mesurerEcran(tester,
              ecran: ecran, theme: theme, echelle: echelle, surcharges: surcharges);
          expect(r.autres, isEmpty, reason: 'erreurs de rendu autres que des débordements');
          expect(r.debordements, isEmpty);
        });
      }
    }
  }
}

// ─── Données ──────────────────────────────────────────────────────────────────

BankrollBet _pari(String id, {String? resultat, double? profit}) => BankrollBet(
      id: id, pronosticId: 'p$id', matchId: 'm$id',
      stakedAmount: 25000, suggestedAmount: 25000, oddsUsed: 1.62, potentialGain: 40500,
      result: resultat, profit: profit, createdAt: DateTime(2026, 9, 28, 18),
      homeTeam: 'Borussia Mönchengladbach', awayTeam: 'Real Sociedad de Fútbol',
      league: 'UEFA Champions League', predictionLabel: 'Domicile ou nul',
      confidenceScore: 4, currency: 'XOF',
    );

BankrollData _bankroll() => BankrollData(
      id: 'b', totalBudget: 1000000, currentBalance: 1015500, currency: 'XOF',
      bets: [
        _pari('1'),
        _pari('2', resultat: 'WIN', profit: 15500),
        _pari('3', resultat: 'LOSS', profit: -25000),
        _pari('4', resultat: 'PUSH', profit: 0),
      ],
      resume: const ResumeParis(total: 4, gagnes: 1, perdus: 1, rembourses: 1,
          enAttente: 1, tauxBrut: 50, profitNet: -9500, misesEnCours: 25000),
      parisAffiches: 4,
    );

List<Override> _compte() => [
      profileProvider.overrideWith((ref) async => {
            'pseudo': 'Parieur_RKBL9', 'phone_number': '+22670000000', 'email': 'demo@pronowin.space',
            'country_code': 'BF', 'first_name': 'Kevin', 'last_name': 'Zongo',
            'birth_date': '2000-01-11T00:00:00.000Z', 'subscription_plan': 'free',
            'created_at': '2026-08-16T00:00:00.000Z', 'referral_code': '1A639B', 'referral_earnings': 0,
          }),
      userStatsProvider.overrideWith((ref) async => {
            'pronostics_suivis': 14, 'paris_gagnes': 9, 'paris_perdus': 5,
            'taux_reussite': 64, 'serie_gagnante': 3,
          }),
      bankrollProvider.overrideWith((ref) async => _bankroll()),
      bankrollStatsProvider.overrideWith((ref) async => null),
      currentSubscriptionProvider.overrideWith((ref) async => <String, dynamic>{'plan': 'free'}),
      referralStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
    ];

List<Override> _paywall() => [
      currentSubscriptionProvider.overrideWith((ref) async => {
            'plan': 'free', 'days_left': 0, 'promo_code': 'CODE77',
            'premium_price_monthly_usd': 10, 'premium_price_annual_usd': 90,
            'betting_platforms': ['1xbet'], 'code_offer_days': 30,
            'payment_methods': <Map<String, dynamic>>[],
          }),
      isStoreBuildProvider.overrideWithValue(false),
      submitProofProvider.overrideWith((ref) => SubmitProofNotifier(Dio())),
    ];
