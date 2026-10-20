import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/fiche_match_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'aides/banc_ecran.dart';

/// « Quand tu cliques sur le champ de texte pour ouvrir le clavier, l'écran
/// tremble deux ou trois fois avant de se stabiliser » (20 octobre 2026).
///
/// Mesuré : le champ vivait au bas de l'onglet Détails, sous l'en-tête
/// repliable. Pendant que le clavier montait, la page défilait à chaque image
/// (309, 308, 305, 311, 339… 533 px) pour garder le champ visible. La saisie
/// se fait désormais dans une feuille posée au-dessus du clavier ; la page
/// derrière ne bouge plus.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  Future<void> ouvrirLaFiche(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    // iPhone 12-15 : 390 × 844 points.
    t.view.physicalSize = const Size(1170, 2532); t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final match = MatchModel.fromJson({'id': 'm', 'league': 'Premier League', 'league_country': 'GB',
      'home_team': 'Arsenal', 'away_team': 'Chelsea', 'status': 'upcoming',
      'match_date': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
      'has_pronostic': true, 'prediction_type': 'HOME_WIN', 'prediction_label': 'Victoire Arsenal',
      'odds_recommended': 1.8, 'confidence_score': 4, 'is_premium': false});
    await t.pumpWidget(ProviderScope(overrides: [...donneesCommunes(),
      matchDetailProvider('m').overrideWith((ref) async => match),
      matchStatsProvider('m').overrideWith((ref) async => null),
      lineupsProvider('m').overrideWith((ref) async => const LineupsData(available: false)),
      injuriesProvider('m').overrideWith((ref) async => []),
      h2hProvider('m').overrideWith((ref) async => throw Exception('none')),
      playerRatingsProvider('m').overrideWith((ref) async => []),
      commentsProvider('m').overrideWith((ref) async => CommentsData(
        vote: const PronosticVoteData(agree: 3, disagree: 1, total: 4),
        comments: [PronosticComment(id: 'c1', userId: 'autre', content: 'Arsenal est en forme.',
          isExpert: false, createdAt: DateTime(2026, 10, 18), userPseudo: 'Awa')])),
    ], child: MaterialApp(theme: AppTheme.dark, home: const MatchDetailPage(matchId: 'm'))));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    await t.scrollUntilVisible(find.byKey(const Key('champ-commentaire')), 300,
        scrollable: find.byType(Scrollable).at(1));
    // Laisser l'élan du défilement retomber : la mesure porte sur le clavier.
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
  }

  /// Les positions de défilement de la page (hors feuille de saisie).
  List<double> positionsPage(WidgetTester t) => find.byType(Scrollable).evaluate()
      .where((e) => find.ancestor(of: find.byWidget(e.widget), matching: find.byType(BottomSheet)).evaluate().isEmpty)
      .map((e) => ((e as StatefulElement).state as ScrollableState).position.pixels)
      .toList();

  Finder saisie() => find.byKey(const Key('saisie-commentaire'));

  testWidgets('toucher le champ : la saisie monte avec le clavier, la page ne bouge pas d\'un pixel', (t) async {
    await ouvrirLaFiche(t);
    final avant = positionsPage(t);
    await t.tap(find.byKey(const Key('champ-commentaire')));
    await t.pump();
    // Le clavier monte en douze images, comme sur un téléphone.
    for (var i = 1; i <= 12; i++) {
      t.view.viewInsets = FakeViewPadding(bottom: 1000.0 * i / 12);
      await t.pump(const Duration(milliseconds: 16));
      expect(positionsPage(t), avant, reason: 'la page a bougé à l\'image $i');
    }
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final editable = t.widget<EditableText>(find.descendant(of: saisie(), matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    // Au-dessus du clavier : 844 − 1000 / 3 points.
    expect(t.getRect(saisie()).bottom, lessThanOrEqualTo(844 - 1000 / 3 + 1));
    expect(positionsPage(t), avant);
  });

  testWidgets('le brouillon survit à la fermeture de la saisie', (t) async {
    await ouvrirLaFiche(t);
    await t.tap(find.byKey(const Key('champ-commentaire')));
    await t.pumpAndSettle();
    await t.enterText(saisie(), 'Arsenal va gagner');
    // Fermer la feuille en touchant au-dessus.
    await t.tapAt(const Offset(195, 60));
    await t.pumpAndSettle();
    expect(saisie(), findsNothing);
    expect(find.text('Arsenal va gagner'), findsOneWidget);   // dans le champ de la section
    await t.tap(find.byKey(const Key('champ-commentaire')));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(saisie()).controller!.text, 'Arsenal va gagner');
  });

  testWidgets('« Répondre » ouvre la saisie, avec le nom de la personne', (t) async {
    await ouvrirLaFiche(t);
    await t.ensureVisible(find.text('Répondre').first);
    await t.tap(find.text('Répondre').first);
    await t.pumpAndSettle();
    expect(saisie(), findsOneWidget);
    expect(find.text('Répondre à Awa'), findsWidgets);
  });

  testWidgets('envoi refusé : le message dans la saisie, le texte gardé', (t) async {
    await ouvrirLaFiche(t);
    await t.tap(find.byKey(const Key('champ-commentaire')));
    await t.pumpAndSettle();
    await t.enterText(saisie(), 'Mon avis');
    await t.tap(find.byKey(const Key('envoyer-commentaire')));
    await t.pumpAndSettle();
    // Le faux serveur des bancs répond 404 à l'envoi.
    expect(find.byKey(const Key('erreur-commentaire')), findsOneWidget);
    expect(t.widget<TextField>(saisie()).controller!.text, 'Mon avis');
  });
}
