import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/config/sans_pari.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/bankroll/domain/couverture.dart';
import 'package:pronowin/features/bankroll/presentation/pages/combines_pages.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/bankroll/presentation/widgets/carte_couverture.dart';
import 'package:pronowin/features/bankroll/presentation/widgets/section_combines.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';

import 'aides/banc_ecran.dart';

/// Couverture enregistrée et coupons combinés (27 novembre 2026).
class _Serveur implements HttpClientAdapter {
  final List<({String methode, String chemin, Map<String, dynamic> corps})> requetes = [];
  Map<String, dynamic> Function(String chemin) reponse = (_) => {};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? corps, Future<void>? annulation) async {
    final brut = corps == null ? '' : utf8.decode(await corps.expand((o) => o).toList());
    requetes.add((
      methode: options.method,
      chemin: options.path,
      corps: brut.isEmpty ? <String, dynamic>{} : jsonDecode(brut) as Map<String, dynamic>,
    ));
    return ResponseBody.fromString(jsonEncode(reponse(options.path)), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

final _fiche = {
  'disponible': true, 'pari_id': 'b1', 'mise': 1000, 'cote': 2, 'devise': 'XOF', 'seuil': 50,
  'selection_fr': 'Plus de 2,5 buts', 'selection_en': 'Over 2.5 goals',
  'inverse_fr': 'Moins de 2,5 buts', 'inverse_en': 'Under 2.5 goals', 'source': 'direct', 'minute': 63,
  'cote_inverse': 4.0, 'mise_couverture': 500, 'gain_garanti': 500, 'gain_potentiel': 1000,
  'part': 0.5, 'seuil_atteint': true, 'enregistree': null, 'remboursable': false,
};

void main() {
  late _Serveur serveur;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('fr');
    await preparerBanc();
  });
  setUp(() => serveur = _Serveur());

  Dio dio() => Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = serveur;

  group('le calcul : récupérer sa mise', () {
    test('1 000 F à 2,00, l\'inverse à 4,00 : 334 F dessus, +666 F ou +2 F', () {
      final c = calculerCouverture(1000, 2, 4, strategie: StrategieCouverture.miseRemboursee)!;
      expect([c.miseCouverture, c.siSelection, c.siInverse], [334, 666, 2]);
      final egal = calculerCouverture(1000, 2, 4)!;
      expect([egal.siSelection, egal.siInverse], [500, 500]);
    });
  });

  group('la carte « Couvrir ma mise »', () {
    Future<void> monter(WidgetTester t, Map<String, dynamic> donnees) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), dioProvider.overrideWithValue(dio())],
        child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(
          child: CarteCouverture(donnees: donnees, cle: 'b1')))),
      ));
      await t.pump();
    }

    testWidgets('la minute du direct, et le choix « Récupérer ma mise »', (t) async {
      await monter(t, _fiche);
      expect(find.textContaining('(en direct, 63e minute)'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('couverture-mise'))).data, contains('Mise 500'));
      await t.tap(find.byKey(const Key('couverture-strategie-mise_remboursee')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('couverture-mise'))).data, contains('Mise 334'));
      expect(t.widget<Text>(find.byKey(const Key('couverture-gain'))).data,
        allOf(contains('Si « Plus de 2,5 buts » passe : +666'), contains('tu récupères ta mise')));
    });

    testWidgets('« J\'ai couvert » enregistre la mise et la cote, et la façon choisie', (t) async {
      await monter(t, _fiche);
      await t.ensureVisible(find.byKey(const Key('couverture-jai-couvert')));
      await t.tap(find.byKey(const Key('couverture-jai-couvert')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('couverture-dialogue-mise')), findsOneWidget);
      await t.tap(find.byKey(const Key('couverture-enregistrer')));
      await t.pumpAndSettle();
      final envoi = serveur.requetes.singleWhere((r) => r.chemin == '/bankroll/couvertures');
      expect(envoi.corps, {'pari_id': 'b1', 'mise': 500.0, 'cote': 4.0, 'strategie': 'gain_egal'});
    });

    testWidgets('une ligne entière : la carte dit quand les deux mises sont remboursées', (t) async {
      await monter(t, {..._fiche, 'remboursable': true,
        'note_remboursement_fr': 'S\'il y a exactement 2 buts, les deux mises sont remboursées : ni gain ni perte.'});
      expect(find.byKey(const Key('couverture-remboursement')), findsOneWidget);
    });

    testWidgets('déjà couverte : la couverture enregistrée, sans calcul ni bouton', (t) async {
      await monter(t, {..._fiche, 'enregistree': {
        'id': 'h1', 'selection_fr': 'Moins de 2,5 buts', 'selection_en': 'Under 2.5 goals',
        'strategie': 'gain_egal', 'mise': 500, 'cote': 4, 'result': null, 'profit': null,
      }});
      expect(find.byKey(const Key('couverture-enregistree')), findsOneWidget);
      expect(find.textContaining('Couverture enregistrée : 500'), findsOneWidget);
      expect(find.byKey(const Key('couverture-jai-couvert')), findsNothing);
      expect(find.byKey(const Key('couverture-mise')), findsNothing);
    });
  });

  group('les combinés', () {
    BankrollCombine combine({String? resultLibre, CouvertureEnregistree? couverture}) => BankrollCombine(
      id: 'c1', stakedAmount: 1500, oddsUsed: 6, potentialGain: 9000, createdAt: DateTime(2026, 11, 27),
      currency: 'XOF', couvertureEnregistree: couverture,
      selections: [
        const SelectionCombine(id: 's1', pronosticId: 'p1', cote: 2, result: 'WIN', predictionLabel: 'Victoire Arsenal',
          homeTeam: 'Arsenal', awayTeam: 'Chelsea'),
        SelectionCombine(id: 's2', libre: true, libreMatch: 'PSG – OM', libreSelection: 'PSG gagne', cote: 3, result: resultLibre),
      ],
    );
    BankrollData bankroll(List<BankrollCombine> combines) => BankrollData(
      id: 'br', totalBudget: 100000, currentBalance: 98500, currency: 'XOF', bets: const [], combines: combines);

    Future<void> monterRoute(WidgetTester t, String route, {required List<Override> overrides}) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), dioProvider.overrideWithValue(dio()), sansPariProvider.overrideWithValue(false), ...overrides],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: GoRouter(initialLocation: route, routes: [
          GoRoute(path: '/bankroll', builder: (_, _) => Scaffold(body: SingleChildScrollView(
            child: Consumer(builder: (_, ref, _) {
              final b = ref.watch(bankrollProvider).valueOrNull;
              return b == null ? const SizedBox() : SectionCombines(bankroll: b);
            })))),
          GoRoute(path: '/bankroll/combine/nouveau', builder: (_, _) => const NouveauCombinePage()),
          GoRoute(path: '/bankroll/combine/:id', builder: (_, s) => CombineDetailPage(id: s.pathParameters['id']!)),
        ])),
      ));
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 50)); }
    }

    testWidgets('la bankroll liste les combinés et mène au détail', (t) async {
      await monterRoute(t, '/bankroll', overrides: [
        bankrollProvider.overrideWith((ref) async => bankroll([combine()])),
      ]);
      expect(find.byKey(const Key('bankroll-nouveau-combine')), findsOneWidget);
      expect(find.text('2 sélections · cote 6.00'), findsOneWidget);
      await t.tap(find.byKey(const Key('combine-c1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('combine-entete-c1')), findsOneWidget);
    });

    testWidgets('une sélection libre se règle à la main', (t) async {
      serveur.reponse = (_) => {'result': null};
      await monterRoute(t, '/bankroll/combine/c1', overrides: [
        bankrollProvider.overrideWith((ref) async => bankroll([combine()])),
        couvertureCombineProvider('c1').overrideWith((ref) async => {'disponible': false, 'raison': 'pas_encore'}),
      ]);
      expect(find.byKey(const Key('combine-regler-s1-WIN')), findsNothing);   // un pronostic PronoWin se règle seul
      await t.tap(find.byKey(const Key('combine-regler-s2-WIN')));
      for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 50)); }
      final envoi = serveur.requetes.singleWhere((r) => r.chemin.endsWith('/resultat'));
      expect(envoi.chemin, '/bankroll/combines/c1/selections/s2/resultat');
      expect(envoi.corps, {'result': 'WIN'});
      expect(find.byKey(const Key('combine-couverture-plus-tard')), findsOneWidget);
    });

    testWidgets('la dernière sélection à jouer : la carte de couverture du combiné', (t) async {
      await monterRoute(t, '/bankroll/combine/c1', overrides: [
        bankrollProvider.overrideWith((ref) async => bankroll([combine(resultLibre: null)])),
        couvertureCombineProvider('c1').overrideWith((ref) async => {
          ..._fiche, 'pari_id': null, 'combine_id': 'c1', 'mise': 1500, 'cote': 6,
        }),
      ]);
      expect(find.byKey(const Key('couverture-c1')), findsOneWidget);
      expect(find.text('COUVRIR MON COMBINÉ'), findsOneWidget);
    });

    testWidgets('composer un combiné : l\'aperçu du serveur, puis l\'envoi avec sa mise', (t) async {
      MatchEntity prono(String id, double cote) => MatchModel.fromJson({
        'id': id, 'league': 'Premier League', 'league_country': 'GB', 'home_team': 'Dom $id', 'away_team': 'Ext $id',
        'status': 'upcoming', 'match_date': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
        'has_pronostic': true, 'prediction_type': 'win1', 'prediction_label': 'Victoire Domicile',
        'odds_recommended': cote, 'confidence_score': 4, 'is_premium': false,
      });
      serveur.reponse = (chemin) => chemin.endsWith('/apercu')
          ? {'mise': 3000, 'note_retenue': 4, 'cote_totale': 3, 'gain_potentiel': 9000, 'devise': 'XOF', 'solde': 100000}
          : {'id': 'c9', 'current_balance': 97000};
      await monterRoute(t, '/bankroll/combine/nouveau', overrides: [
        bankrollProvider.overrideWith((ref) async => bankroll(const [])),
        pronosticsCombinablesProvider.overrideWith((ref) async => [prono('m1', 2), prono('m2', 1.5)]),
      ]);
      await t.tap(find.byKey(const Key('combine-prono-m1')));
      await t.pump();
      await t.tap(find.byKey(const Key('combine-prono-m2')));
      for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 50)); }
      expect(t.widget<Text>(find.byKey(const Key('combine-cote-totale'))).data, contains('3.00'));
      expect(t.widget<Text>(find.byKey(const Key('combine-mise'))).data, contains('Mise 3'));

      await t.tap(find.byKey(const Key('combine-valider')));
      for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 50)); }
      final envoi = serveur.requetes.singleWhere((r) => r.chemin == '/bankroll/combines');
      expect(envoi.corps, {
        'selections': [{'pronostic_id': 'm1'}, {'pronostic_id': 'm2'}],
        'staked_amount': 3000,
      });
    });
  });
}
