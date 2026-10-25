import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/historique_page.dart';
import 'package:pronowin/l10n/app_strings.dart';

import 'aides/banc_ecran.dart';

/// La page Historique refaite (25 octobre 2026).
///
/// Le serveur n'envoie que des pronostics réglés. La page avait un filtre
/// « En attente » toujours vide, un taux de réussite qui comptait les
/// remboursés comme des défaites, des lignes qu'on ne pouvait pas ouvrir, et
/// un bouton retour qui ne menait nulle part depuis la notification « Bilan
/// de la semaine ».
Map<String, dynamic> _entree(String id, String resultat, {int joursAvant = 1, bool premium = false,
    bool verrouille = false, String libelle = 'Spain gagne'}) => {
  'id': id, 'result': resultat, 'predictionLabel': libelle, 'oddsRecommended': 1.8,
  'isPremium': premium, 'locked': verrouille,
  'match': {
    'id': 'm$id', 'homeTeam': 'Spain', 'awayTeam': 'Czechia', 'league': 'UEFA Nations League',
    'homeScore': 2, 'awayScore': 1,
    'matchDate': DateTime.now().subtract(Duration(days: joursAvant)).toUtc().toIso8601String(),
  },
};

void main() {
  setUpAll(() async {
    await preparerBanc();
    await initializeDateFormatting('fr');
  });

  group('le bilan', () {
    test('réussite sur les seuls gagnés et perdus, à partir de dix — un remboursé n\'est pas une défaite', () {
      final l = [
        for (var i = 0; i < 9; i++) _entree('w$i', 'WIN'),
        for (var i = 0; i < 3; i++) _entree('l$i', 'LOSS'),
        _entree('p1', 'PUSH'), _entree('p2', 'PUSH'),
      ];
      final b = BilanHistorique.de(l);
      expect([b.gagnes, b.perdus, b.rembourses, b.tranches], [9, 3, 2, 12]);
      expect(b.taux, 75, reason: 'et non 9 / 14 = 64 %');
      expect(BilanHistorique.de(l.take(9)).taux, isNull, reason: 'neuf pronostics : pas de taux');
    });

    test('série en cours : du plus récent, un remboursé ne la coupe pas ; meilleure série', () {
      // Du plus récent au plus ancien, comme le serveur.
      final l = ['WIN', 'PUSH', 'WIN', 'LOSS', 'WIN', 'WIN', 'WIN', 'PUSH', 'WIN', 'LOSS']
          .indexed.map((x) => _entree('${x.$1}', x.$2)).toList();
      final b = BilanHistorique.de(l);
      expect(b.serieEnCours, 2);
      expect(b.meilleureSerie, 4);
      expect(BilanHistorique.de([_entree('a', 'LOSS'), _entree('b', 'WIN')]).serieEnCours, 0);
    });
  });

  Future<GoRouter> monter(WidgetTester t, List<Map<String, dynamic>> entrees, {String depart = '/historique'}) async {
    t.view.physicalSize = const Size(390 * 3, 1700 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final routeur = GoRouter(initialLocation: depart, routes: [
      GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('ACCUEIL'))),
      GoRoute(path: '/historique', builder: (_, _) => const HistoriquePage()),
      GoRoute(path: '/pronostics/:id', builder: (_, s) => Scaffold(body: Text('fiche ${s.pathParameters['id']}'))),
      GoRoute(path: '/compte/activer-premium', builder: (_, _) => const Scaffold(body: Text('OFFRE PREMIUM'))),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), historiqueProvider.overrideWith((ref, jours) async => entrees)],
      child: MaterialApp.router(
        routerConfig: routeur, theme: AppTheme.light, locale: const Locale('fr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [AppStrings.delegate, GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      ),
    ));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 100)); }
    return routeur;
  }

  final douze = [
    for (var i = 0; i < 9; i++) _entree('w$i', 'WIN', joursAvant: i < 2 ? 0 : 3),
    for (var i = 0; i < 3; i++) _entree('l$i', 'LOSS', joursAvant: 1),
    _entree('p1', 'PUSH', joursAvant: 1),
  ];

  testWidgets('l\'en-tête : 75 %, sur 12, série en cours ; plus de filtre « En attente »', (t) async {
    await monter(t, douze);
    expect(t.widget<Text>(find.byKey(const Key('historique-taux'))).data, '75 %');
    expect(find.text('sur 12 pronostics gagnés ou perdus'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('historique-serie'))).data, '2');
    expect(find.text('En attente'), findsNothing);
    expect(find.byKey(const Key('historique-filtre-push')), findsOneWidget);
    expect(find.text('1 remboursé'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('par jour : « Aujourd\'hui », « Hier », puis le jour en toutes lettres, avec son bilan', (t) async {
    await monter(t, douze);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^[A-Z][a-zéû]+ \d{1,2} [a-zéû]+$')), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget, reason: 'aujourd\'hui : deux gagnés sur deux');
    expect(find.text('0/3'), findsOneWidget, reason: 'hier : trois perdus, un remboursé à part');
  });

  testWidgets('filtre Remboursés : le seul remboursé', (t) async {
    await monter(t, douze);
    await t.tap(find.byKey(const Key('historique-filtre-push')));
    await t.pumpAndSettle();
    expect(find.text('Remboursé'), findsOneWidget);
    expect(find.text('Gagné'), findsNothing);
    expect(find.text('Perdu'), findsNothing);
  });

  testWidgets('gratuits et Premium : la réussite de chacun, et le filtre', (t) async {
    await monter(t, [
      for (var i = 0; i < 8; i++) _entree('g$i', 'WIN'),
      for (var i = 0; i < 2; i++) _entree('h$i', 'LOSS'),
      for (var i = 0; i < 9; i++) _entree('v$i', 'WIN', premium: true, libelle: 'Plus de 2,5 buts'),
      _entree('x1', 'LOSS', premium: true, libelle: 'Plus de 2,5 buts'),
    ]);
    expect(find.text('Gratuits : 80 %'), findsOneWidget);
    expect(find.text('Premium : 90 %'), findsOneWidget);
    expect(find.textContaining(' gagne'), findsWidgets);
    await t.tap(find.byKey(const Key('historique-niveau-premium')));
    await t.pumpAndSettle();
    expect(find.textContaining(' gagne'), findsNothing);
    expect(find.text('Plus de 2,5 buts'), findsWidgets);
  });

  testWidgets('une ligne ouvre la fiche du match ; verrouillée, l\'offre Premium', (t) async {
    await monter(t, [_entree('a1', 'WIN'), _entree('a2', 'LOSS', premium: true, verrouille: true, libelle: 'Pronostic Premium')]);
    await t.tap(find.byKey(const Key('historique-a1')));
    await t.pumpAndSettle();
    expect(find.text('fiche a1'), findsOneWidget);
  });

  testWidgets('ouverte par la notification « Bilan de la semaine » : le retour mène à l\'accueil', (t) async {
    await monter(t, douze);
    await t.tap(find.byTooltip('Retour'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('ACCUEIL'), findsOneWidget);
  });

  testWidgets('rien sur la période : un message, pas de bilan à 0 %', (t) async {
    await monter(t, const []);
    expect(find.text('Aucun pronostic réglé sur cette période'), findsOneWidget);
    expect(find.byKey(const Key('historique-bilan')), findsNothing);
  });

  for (final echelle in [1.0, 1.6]) {
    testWidgets('écran étroit (320 px), texte ${(echelle * 100).round()} % : rien ne déborde', (t) async {
      t.view.physicalSize = const Size(320 * 2, 1400 * 2);
      t.view.devicePixelRatio = 2;
      t.platformDispatcher.textScaleFactorTestValue = echelle;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(ProviderScope(
        overrides: [...donneesCommunes(), historiqueProvider.overrideWith((ref, jours) async => [
          _entree('1', 'WIN', libelle: 'Joueur va marquer un but à tout moment : Mikel Oyarzabal'),
          _entree('2', 'PUSH', premium: true),
          ...douze,
        ])],
        child: MaterialApp(theme: AppTheme.dark, home: const HistoriquePage()),
      ));
      for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 100)); }
      expect(t.takeException(), isNull);
    });
  }
}
