import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/providers/match_info_provider.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail_page.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'aides/banc_ecran.dart';

void main() {
  setUpAll(preparerBanc);
  final capture =
      jsonDecode(File('test/fixtures/match_info_live.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'relevé réel Banfield, texte 180%, thème ${theme.brightness.name}',
      (t) async {
        final snapshots = capture['snapshots'] as List;
        final first = MatchInfo.fromJson(
          snapshots.first as Map<String, dynamic>,
        );
        final last = MatchInfo.fromJson(snapshots.last as Map<String, dynamic>);
        expect(last.elapsed, greaterThan(first.elapsed!));
        final r = await mesurerEcran(
          t,
          ecran: Scaffold(
            body: SingleChildScrollView(child: informationsMatchSeules('m')),
          ),
          theme: theme,
          echelle: 1.8,
          surcharges: [
            matchInfoProvider('m').overrideWith((ref) async => last),
          ],
          verifier: () {
            expect(
              find.text('Estadio Florencio Sola · Buenos Aires'),
              findsOneWidget,
            );
            expect(find.text('Leandro Rey Hilfer'), findsOneWidget);
            expect(find.text('Première mi-temps (en cours)'), findsOneWidget);
            expect(find.text('Mi-temps'), findsNothing);
            expect(find.text('Tirs au but'), findsNothing);
            expect(find.text('5 min'), findsOneWidget);
          },
        );
        expect(r.debordements, isEmpty);
        expect(r.autres, isEmpty);
      },
    );
  }
  testWidgets(
    'avant match: aucun score prématuré même si le fournisseur renvoie zéro',
    (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            matchInfoProvider('m').overrideWith(
              (ref) async => const MatchInfo(
                phase: 'NS',
                scores: {'halftime': PeriodScore(home: 0, away: 0)},
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: informationsMatchSeules('m')),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      expect(find.text('À venir'), findsOneWidget);
      expect(find.text('0 – 0'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  test('absence, zéro et tirs au but restent distincts', () {
    final data = MatchInfo.fromJson({
      'phase': 'PEN',
      'scores': {
        'halftime': {'home': 0, 'away': 0},
        'penalty': {'home': 5, 'away': 4},
        'extratime': {'home': 2},
      },
    });
    expect(data.scores['halftime']!.label, '0 – 0');
    expect(data.scores['fulltime']!.available, false);
    expect(data.scores['penalty']!.label, '5 – 4');
    expect(data.scores['extratime']!.label, '2 – —');
  });
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'informations complètes, texte 180%, thème ${theme.brightness.name}',
      (t) async {
        final r = await mesurerEcran(
          t,
          ecran: Scaffold(
            body: SingleChildScrollView(child: informationsMatchSeules('m')),
          ),
          theme: theme,
          echelle: 1.8,
          surcharges: [
            matchInfoProvider('m').overrideWith((ref) async => sample),
          ],
          verifier: () {
            expect(find.text('Terminé aux tirs au but'), findsOneWidget);
            expect(find.text('5 – 4'), findsOneWidget);
            expect(find.text('Temps réglementaire'), findsOneWidget);
          },
        );
        expect(r.debordements, isEmpty);
        expect(r.autres, isEmpty);
      },
    );
  }
  testWidgets('erreur puis réessai, sans inventer de données', (t) async {
    var calls = 0;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          matchInfoProvider('m').overrideWith((ref) async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return const MatchInfo(phase: 'NS');
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: informationsMatchSeules('m')),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(
      find.text('Informations du match momentanément indisponibles.'),
      findsOneWidget,
    );
    await t.tap(find.text('Réessayer'));
    await t.pump();
    await t.pump();
    expect(find.text('À venir'), findsOneWidget);
    expect(find.text('Stade'), findsNothing);
    expect(find.text('0 – 0'), findsNothing);
    expect(calls, 2);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
  testWidgets('relevé périmé visible et libellés anglais', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          matchInfoProvider('m').overrideWith(
            (ref) async => const MatchInfo(
              phase: 'P',
              stale: true,
              scores: {'penalty': PeriodScore(home: 1, away: 0)},
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: informationsMatchSeules('m')),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.text('Penalty shootout in progress'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('interrupted'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
}

const sample = MatchInfo(
  venue: 'Stade international avec un nom particulièrement long',
  city: 'Ouagadougou',
  referee: 'Arbitre principal, assistant vidéo',
  round: 'Regular Season - Group B - Round 15',
  season: 2026,
  phase: 'PEN',
  homeTeam: 'Home',
  awayTeam: 'Away',
  scores: {
    'halftime': PeriodScore(home: 0, away: 0),
    'fulltime': PeriodScore(home: 1, away: 1),
    'extratime': PeriodScore(home: 2, away: 2),
    'penalty': PeriodScore(home: 5, away: 4),
  },
);
