import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/equipes_suivies.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';

import 'aides/banc_ecran.dart';

/// Suivre des équipes (7 novembre 2026, comme FotMob) : leurs prochains
/// matchs dans « Suivis ».
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  const bayern = EquipeSuivie(id: 157, nom: 'Bayern München',
      logo: 'https://media.api-sports.io/football/teams/157.png', competition: 'BL1');

  MatchEntity match(String id, String dom, int idDom, String ext, int idExt, DateTime date,
      {MatchStatus statut = MatchStatus.upcoming, bool prono = false}) => MatchEntity(
        id: id, league: 'Bundesliga', leagueCountry: 'BL1',
        homeTeam: dom, awayTeam: ext,
        homeTeamLogo: 'https://media.api-sports.io/football/teams/$idDom.png',
        awayTeamLogo: 'https://media.api-sports.io/football/teams/$idExt.png',
        matchDate: date, status: statut,
        predictionType: PredictionType.win1, predictionLabel: '',
        oddsRecommended: 0, oddsHome: 0, oddsDraw: 0, oddsAway: 0,
        confidenceScore: 0, isPremium: false, homeFormPoints: 0, awayFormPoints: 0,
        hasPronostic: prono,
      );

  test('une équipe suivie se relit telle qu\'enregistrée ; la déconnexion l\'efface', () async {
    expect(EquipeSuivie.fromJson(bayern.toJson())?.nom, 'Bayern München');
    expect(EquipeSuivie.fromJson({'id': 'x'}), isNull);
    SharedPreferences.setMockInitialValues({cleFavorisEquipes('u1'): ['{"id":157,"nom":"Bayern"}']});
    await effacerFavorisLocaux(resilierSujets: false);
    expect((await SharedPreferences.getInstance()).getStringList(cleFavorisEquipes('u1')), isNull);
  });

  test('suivre puis ne plus suivre : enregistré pour le compte connecté', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: donneesCommunes());
    addTearDown(c.dispose);
    await c.read(favorisProvider.future);
    await c.read(favorisProvider.notifier).basculerEquipe(bayern);
    expect(c.read(favorisProvider).value!.suitEquipe(157), isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList(cleFavorisEquipes('u1')), hasLength(1));
    await c.read(favorisProvider.notifier).basculerEquipe(bayern);
    expect(c.read(favorisProvider).value!.equipes, isEmpty);
  });

  test('prochains matchs : ceux de l\'équipe seulement (pas Bayern II), dans les deux semaines, le direct d\'abord', () async {
    final maintenant = DateTime.now();
    final c = ProviderContainer(overrides: [
      ...donneesCommunes(favoris: () => _Suivies([bayern])),
      rechercheMatchsProvider.overrideWith((ref, terme) async => [
        match('loin', 'Bayern München', 157, 'Köln', 192, maintenant.add(const Duration(days: 30))),
        match('ii', 'Bayern München II', 4000, 'Unterhaching', 4001, maintenant.add(const Duration(days: 2))),
        match('demain', 'Mainz 05', 164, 'Bayern München', 157, maintenant.add(const Duration(days: 1))),
        match('direct', 'Bayern München', 157, 'Freiburg', 160, maintenant.subtract(const Duration(minutes: 30)),
            statut: MatchStatus.live),
      ]),
    ]);
    addTearDown(c.dispose);
    await c.read(favorisProvider.future);
    final liste = await c.read(matchsEquipesSuiviesProvider.future);
    expect(liste.map((m) => m.id), ['direct', 'demain']);
  });

  Future<void> monter(WidgetTester t, FavorisNotifier Function() favoris, {List<MatchEntity> recherche = const []}) async {
    t.view.physicalSize = const Size(720, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...donneesCommunes(favoris: favoris),
        rechercheMatchsProvider.overrideWith((ref, terme) async => recherche),
      ],
      child: MaterialApp(theme: AppTheme.dark,
        home: Scaffold(body: ListView(padding: const EdgeInsets.all(14),
          children: const [EquipesSuiviesSection()]))),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('« Mes équipes » et leurs prochains matchs, avec la date', (t) async {
    final demain = DateTime.now().add(const Duration(days: 1));
    await monter(t, () => _Suivies([bayern]),
      recherche: [match('demain', 'Mainz 05', 164, 'Bayern München', 157, demain)]);
    expect(find.text('Mes équipes'), findsOneWidget);
    expect(find.byKey(const Key('equipe-suivie-157')), findsOneWidget);
    expect(find.text('Mainz 05'), findsOneWidget);
    expect(find.text('${demain.day.toString().padLeft(2, '0')}/${demain.month.toString().padLeft(2, '0')}'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('sans équipe ni écusson connu : aucune suggestion inventée', (t) async {
    SharedPreferences.setMockInitialValues({});
    // La liste du jour du banc : deux matchs avec pronostic, sans logo.
    await monter(t, () => _Suivies(const []));
    // Les matchs du banc n'ont pas d'écusson : aucune suggestion possible.
    expect(find.text('Suis tes équipes'), findsNothing);
    expect(find.text('Mes équipes'), findsNothing);
  });
}

class _Suivies extends FavorisNotifier {
  final List<EquipeSuivie> equipes;
  _Suivies(this.equipes);
  @override
  Future<EtatFavoris> build() async => EtatFavoris(equipes: equipes);
}
