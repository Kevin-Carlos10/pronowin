import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/bankroll/presentation/pages/bet_detail_page.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// La fiche d'un pari dit où il en est, montre le match, et mène à lui.
///
/// Elle affichait un sablier d'un quart d'écran, la date du pari sous le nom
/// du match (comme si c'était celle du match), la cote deux fois, la
/// confiance en bleu « information », et ne menait nulle part.
/// Un texte qui contient [attendu], espaces insécables compris : les montants
/// s'écrivent « 5 233 » avec une espace fine.
Finder montant(String attendu) => find.byWidgetPredicate((w) =>
    w is Text && (w.data ?? '').replaceAll(RegExp(r'\s'), '').contains(attendu.replaceAll(' ', '')));

void main() {
  setUpAll(preparerBanc);

  BankrollBet pari({String? resultat, double? profit, String statut = 'upcoming', Duration dans = const Duration(hours: 5, minutes: 35)}) =>
      BankrollBet(
        id: 'b1', pronosticId: 'p42', matchId: 'm42',
        stakedAmount: 5233, suggestedAmount: 5233, oddsUsed: 1.52, potentialGain: 7954,
        result: resultat, profit: profit,
        // Le pari a été placé la veille : sa date ne doit pas passer pour
        // celle du match.
        createdAt: DateTime(2026, 9, 30, 15, 9),
        homeTeam: 'Wales', awayTeam: 'Norway', league: 'UEFA Nations League',
        matchDate: DateTime.now().add(dans), matchStatus: statut,
        homeScore: statut == 'upcoming' ? null : 1, awayScore: statut == 'upcoming' ? null : 0,
        predictionLabel: 'Joueur va marquer : Erling Braut Haaland',
        confidenceScore: 5, confidencePct: 88, currency: 'XOF',
      );

  Future<void> monter(WidgetTester t, BankrollBet b, {ThemeData? theme}) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: theme ?? AppTheme.dark,
        locale: const Locale('fr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => BetDetailPage(bet: b)),
          GoRoute(path: '/pronostics/:id',
              builder: (_, s) => Scaffold(body: Text('analyse ${s.pathParameters['id']}'))),
        ]),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('en attente : ce qu\'on attend, pas un sablier muet', (t) async {
    await monter(t, pari());
    expect(find.text('En attente'), findsOneWidget);
    expect(find.textContaining("Coup d'envoi dans 5 h"), findsOneWidget);
  });

  testWidgets('match en cours : le score dans l\'en-tête', (t) async {
    await monter(t, pari(statut: 'live', dans: const Duration(minutes: -30)));
    expect(find.text('Match en cours · 1 – 0'), findsOneWidget);
  });

  testWidgets('sous le match, la date du match — plus celle du pari', (t) async {
    await monter(t, pari());
    // Le pari date du 30 septembre ; seul le pied de l'en-tête le dit.
    expect(find.textContaining('30 septembre 2026'), findsOneWidget);
    expect(find.textContaining('Pari placé le'), findsOneWidget);
  });

  testWidgets('les deux issues, côte à côte, et la cote une seule fois', (t) async {
    await monter(t, pari());
    expect(find.text('Si gagné'), findsOneWidget);
    expect(find.text('Si perdu'), findsOneWidget);
    expect(montant('-5 233'), findsOneWidget);
    expect(find.textContaining('1.52'), findsOneWidget);
    expect(find.text('Indice de confiance 88 %'), findsOneWidget);
    expect(find.textContaining('/5'), findsNothing);
  });

  testWidgets('réglé gagnant : le résultat net en tête', (t) async {
    await monter(t, pari(resultat: 'WIN', profit: 2721, statut: 'finished'));
    expect(find.text('Gagné'), findsOneWidget);
    expect(montant('+2 721'), findsWidgets);
    expect(find.text('Si perdu'), findsNothing);
  });

  testWidgets('la carte du match et le bouton mènent à l\'analyse', (t) async {
    await monter(t, pari());
    await t.tap(find.text('Wales'));
    await t.pumpAndSettle();
    expect(find.text('analyse p42'), findsOneWidget);
  });

  for (final (nomTheme, theme) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
    for (final echelle in [1.0, 1.8]) {
      for (final (cas, b) in [('en attente', pari()), ('gagné', pari(resultat: 'WIN', profit: 2721, statut: 'finished'))]) {
        testWidgets('$cas · $nomTheme · texte ${(echelle * 100).round()} % · 360 px', (t) async {
          final r = await mesurerEcran(t, ecran: BetDetailPage(bet: b), theme: theme, echelle: echelle);
          expect(r.autres, isEmpty);
          expect(r.debordements, isEmpty);
        });
      }
    }
  }
}
