import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';
import 'package:pronowin/shared/widgets/alertes_match.dart';
import 'aides/banc_ecran.dart';

/// Les alertes au choix pour un match suivi (27 octobre 2026) : 145 alertes
/// de but pour 8 lues sur une semaine. Le match suivi, la cloche de sa fiche
/// ouvre le choix.
class _Carnet extends FavorisNotifier {
  _Carnet(this.depart);
  final Set<String> depart;
  @override
  Future<EtatFavoris> build() async => EtatFavoris(matchIds: depart);
  @override
  Future<void> basculerMatch(String matchId) async {
    final ids = {...state.value!.matchIds};
    ids.contains(matchId) ? ids.remove(matchId) : ids.add(matchId);
    state = AsyncData(EtatFavoris(matchIds: ids));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  late List<List<String>> enregistres;

  Future<ProviderContainer> ouvrir(WidgetTester t, {required bool suivi, List<String>? serveur = const ['buts', 'fin_de_match'],
      bool echec = false}) async {
    SharedPreferences.setMockInitialValues({'astuce_suivre_match_vue': true});
    t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    enregistres = [];
    final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': 'upcoming',
      'match_date': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
      'has_pronostic': true, 'prediction_type': 'HOME_WIN', 'prediction_label': 'Victoire Arsenal',
      'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false});
    await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(favoris: () => _Carnet(suivi ? {'m'} : {})),
      matchDetailProvider('m').overrideWith((ref) async => match),
      matchStatsProvider('m').overrideWith((ref) async => null),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
      playerRatingsProvider('m').overrideWith((ref) async => []),
      articlesDuMatchProvider('m').overrideWith((ref) async => null),
      votesMatchProvider('m').overrideWith((ref) async => null),
      alertesMatchProvider('m').overrideWith((ref) async => serveur),
      choisirAlertesProvider.overrideWithValue((id, alertes) async {
        if (echec) throw Exception('hors ligne');
        enregistres.add(alertes);
        return alertes;
      }),
    ], child: MaterialApp(theme: AppTheme.dark, home: const MatchDetailPage(matchId: 'm'))));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    return ProviderScope.containerOf(t.element(find.byType(MatchDetailPage)));
  }

  bool active(WidgetTester t, String c) =>
      t.widget<SwitchListTile>(find.byKey(Key('alerte-$c'))).value;

  testWidgets('match suivi : la cloche ouvre ses alertes, telles que gardées', (t) async {
    await ouvrir(t, suivi: true);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feuille-alertes')), findsOneWidget);
    expect(find.text('Alertes pour ce match'), findsOneWidget);
    expect(find.text('Arsenal – Chelsea'), findsOneWidget);
    expect(active(t, 'buts'), isTrue);
    expect(active(t, 'fin_de_match'), isTrue);
    expect(active(t, 'cartons'), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('un interrupteur, un raccourci : enregistrés aussitôt, dans l\'ordre du catalogue', (t) async {
    await ouvrir(t, suivi: true);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alerte-coup_envoi')));
    await t.pumpAndSettle();
    expect(enregistres.last, ['coup_envoi', 'buts', 'fin_de_match']);
    await t.tap(find.byKey(const Key('alertes-raccourci-fin_de_match')));
    await t.pumpAndSettle();
    expect(enregistres.last, ['fin_de_match']);
    expect(active(t, 'buts'), isFalse);
    await t.tap(find.byKey(const Key('alertes-raccourci-tout')));
    await t.pumpAndSettle();
    expect(enregistres.last, categoriesAlerte);
  });

  testWidgets('enregistrement refusé : le choix d\'avant revient, avec un message', (t) async {
    await ouvrir(t, suivi: true, echec: true);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alerte-cartons')));
    await t.pumpAndSettle();
    expect(active(t, 'cartons'), isFalse);
    expect(find.byKey(const Key('alertes-erreur')), findsOneWidget);
  });

  testWidgets('« Ne plus suivre » : la feuille se ferme, le match n\'est plus suivi', (t) async {
    final c = await ouvrir(t, suivi: true);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertes-ne-plus-suivre')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feuille-alertes')), findsNothing);
    expect(c.read(favorisProvider).value!.matchIds, isNot(contains('m')));
  });

  testWidgets('match pas encore suivi : la cloche le suit, sans ouvrir la feuille', (t) async {
    final c = await ouvrir(t, suivi: false);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feuille-alertes')), findsNothing);
    expect(c.read(favorisProvider).value!.matchIds, contains('m'));
  });

  testWidgets('serveur muet : la feuille le dit, « Ne plus suivre » reste possible', (t) async {
    await ouvrir(t, suivi: true, serveur: null);
    await t.tap(find.byKey(const Key('suivre-match')));
    await t.pumpAndSettle();
    expect(find.text("Alertes indisponibles pour l'instant."), findsOneWidget);
    expect(find.byKey(const Key('alertes-ne-plus-suivre')), findsOneWidget);
  });
}
