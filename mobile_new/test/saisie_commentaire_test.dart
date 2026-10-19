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

/// « Lorsqu'on clique pour saisir un commentaire dans un match, ça fait un
/// bug » (19 octobre 2026). Le champ est tout en bas de l'onglet Détails, dans
/// la fiche à en-tête repliable : toucher le champ, puis le clavier qui monte.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await preparerBanc();
  });

  Future<Finder> ouvrirLeChamp(WidgetTester t) async {
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

    final champ = find.byWidgetPredicate((w) => w is TextField
        && w.decoration?.hintText == 'Partage ton avis sur ce pronostic…');
    await t.scrollUntilVisible(champ, 300, scrollable: find.byType(Scrollable).at(1));
    await t.pump(const Duration(milliseconds: 300));
    return champ;
  }

  testWidgets('toucher le champ puis le clavier : focus gardé, champ visible au-dessus du clavier', (t) async {
    final champ = await ouvrirLeChamp(t);
    await t.tap(champ);
    await t.pump();
    // Le clavier monte en plusieurs images, comme sur un téléphone.
    for (final h in [300.0, 600.0, 900.0, 1000.0]) {
      t.view.viewInsets = FakeViewPadding(bottom: h);
      await t.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }

    expect(t.takeException(), isNull);
    final editable = t.widget<EditableText>(find.descendant(of: champ, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue, reason: 'le champ a perdu le focus : le clavier se referme');
    final bas = t.getRect(champ).bottom;
    expect(bas, lessThanOrEqualTo(844 - 1000 / 3 + 1), reason: 'le champ est caché sous le clavier ($bas)');

    await t.enterText(champ, 'Je suis d\'accord');
    await t.pump();
    expect(find.text('Je suis d\'accord'), findsOneWidget);
  });

  testWidgets('clavier ouvert pendant deux relevés du score (10 s) : le texte et le focus restent', (t) async {
    final champ = await ouvrirLeChamp(t);
    await t.tap(champ);
    await t.pump();
    t.view.viewInsets = const FakeViewPadding(bottom: 1000);
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(champ, 'Bon prono');
    for (var i = 0; i < 25; i++) { await t.pump(const Duration(seconds: 1)); }
    expect(t.takeException(), isNull);
    final editable = t.widget<EditableText>(find.descendant(of: champ, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'Bon prono');
  });
}
