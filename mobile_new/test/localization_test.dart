import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/l10n/catalog_en.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/core/utils/date_formatter.dart';
import 'package:pronowin/core/network/failures.dart';
import 'package:pronowin/core/network/dio_exception_handler.dart';
import 'package:dio/dio.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:pronowin/features/parametres/presentation/providers/security_provider.dart';
import 'package:pronowin/features/parametres/presentation/pages/parametres_page.dart';
import 'package:pronowin/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:pronowin/shared/utils/montant.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';
import 'package:pronowin/features/tutoriels/domain/entities/tutorial_entity.dart';

class _SettingsHarness extends ConsumerWidget {
  const _SettingsHarness({this.home = const ParametresPage()});
  final Widget home;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    locale: ref.watch(localeProvider),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.dark,
    home: home,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setCurrentLanguage('fr');
    // Sans choix enregistré, l'app suit la langue du téléphone : ces scénarios
    // partent d'un téléphone réglé en français.
    TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
  });
  tearDown(() {
    AppStrings.setCurrentLanguage('fr');
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocaleTestValue();
  });

  test('sans choix dans l’app, la langue du téléphone ; un choix l’emporte toujours', () {
    expect(AppStrings.languePreferee(null, const Locale('en', 'US')), 'en');
    expect(AppStrings.languePreferee(null, const Locale('fr', 'BF')), 'fr');
    // Les langues sans traduction retombent sur le français.
    expect(AppStrings.languePreferee(null, const Locale('es')), 'fr');
    expect(AppStrings.languePreferee('fr', const Locale('en', 'US')), 'fr');
    expect(AppStrings.languePreferee('en', const Locale('fr')), 'en');
  });

  testWidgets('un téléphone en anglais ouvre l’app en anglais, sans réglage', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bioAvailableProvider.overrideWith((ref) async => false),
        appVersionProvider.overrideWith((ref) async => 'v1.0.16'),
      ],
      child: const _SettingsHarness(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Paramètres'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('catalogue généré complet, avec les mêmes paramètres', () {
    final source =
        (jsonDecode(File('lib/l10n/en.json').readAsStringSync()) as Map)
            .cast<String, String>();
    expect(englishMessages, source);
    Set<String> placeholders(String s) =>
        RegExp(r'\{arg\d+\}').allMatches(s).map((m) => m[0]!).toSet();
    for (final entry in source.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      expect(
        placeholders(entry.value),
        placeholders(entry.key),
        reason: entry.key,
      );
    }
  });

  test('les paramètres utilisateurs sont substitués une seule fois', () {
    const en = AppStrings(Locale('en'));
    expect(en.text('Erreur : {arg0}', ['{arg1}']), 'Error: {arg1}');
    expect(
      en.text('Pas de catalogue pour ce texte'),
      'Pas de catalogue pour ce texte',
    );
    expect(
      en.text('{arg0} contre {arg1}', ['Équipe A', 'Équipe B']),
      'Équipe A vs Équipe B',
    );
    expect(AppStrings.normaliseLanguage('en-GB'), 'en');
    expect(AppStrings.normaliseLanguage('pt'), 'fr');
  });

  test(
    'les dates, montants et erreurs suivent la langue sans changer la valeur',
    () async {
      await initializeDateFormatting('fr');
      await initializeDateFormatting('en');
      final date = DateTime(2026, 9, 30, 18, 45);
      const failure = NetworkFailure();
      expect(montantExact(2025), '2\u202f025');
      expect(AppDateFormatter.shortDate(date), contains('sept.'));
      AppStrings.setCurrentLanguage('en');
      expect(montantExact(2025), '2,025');
      expect(decimalFr(1.5), '1.5');
      expect(AppDateFormatter.shortDate(date), contains('Sep'));
      expect(failure.message, 'No internet connection. Check your network.');
      AppStrings.setCurrentLanguage('fr');
      expect(failure.message, 'Pas de connexion internet. Vérifie ton réseau.');
    },
  );

  test('pluriels français et anglais, y compris zéro', () {
    const fr = AppStrings(Locale('fr'));
    const en = AppStrings(Locale('en'));
    String matches(AppStrings strings, int n) =>
        strings.count(n, one: '{arg0} match', other: '{arg0} matchs');
    expect(matches(fr, 0), '0 match');
    expect(matches(fr, 2), '2 matchs');
    expect(matches(en, 0), '0 matches');
    expect(matches(en, 1), '1 match');
    expect(matches(en, 2), '2 matches');
  });

  test('une erreur existante suit aussi un retour de l’anglais au français', () {
    AppStrings.setCurrentLanguage('en');
    final failure = handleDioException(DioException(
      requestOptions: RequestOptions(path: '/matches'),
      type: DioExceptionType.connectionTimeout,
    ));
    expect(failure.message, englishMessages['Connexion trop lente. Vérifie ton réseau.']);
    AppStrings.setCurrentLanguage('fr');
    expect(failure.message, 'Connexion trop lente. Vérifie ton réseau.');
    const server = ServerFailure('Erreur serveur ({arg0}). Réessaie plus tard.', [503]);
    expect(server.message, contains('503'));
    AppStrings.setCurrentLanguage('en');
    expect(server.message, 'Server error (503). Try again later.');
  });

  test('la langue ne change ni les identifiants ni le contenu publié', () {
    final tutorial = TutorialEntity.fromJson({
      'id': 't1',
      'title': 'Analyse',
      'description': 'Texte rédigé par un auteur',
      'level': 'intermediate',
      'category': 'statistics',
      'author_name': 'Victoire',
      'article_content': 'Article en français',
    });
    final stored = tutorial.toJson();
    expect(tutorial.levelLabel, 'Intermédiaire');
    AppStrings.setCurrentLanguage('en');
    expect(tutorial.levelLabel, 'Intermediate');
    expect(tutorial.categoryLabel, 'Statistics');
    expect(tutorial.toJson(), stored);
    expect(tutorial.title, 'Analyse');
    expect(tutorial.authorName, 'Victoire');
    expect(MatchEntity.confidenceDisplay(4), '4/5');
    expect(MatchEntity.labelForConfidence(4), 'High');
  });

  for (final status in MatchStatus.values) {
    testWidgets(
      'carte en anglais, petit écran et texte agrandi : ${status.name}',
      (tester) async {
        AppStrings.setCurrentLanguage('en');
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final match = MatchEntity(
          id: 'm1',
          league: 'UEFA Champions League',
          leagueCountry: 'EU',
          homeTeam: 'Borussia Mönchengladbach',
          awayTeam: 'Real Sociedad de Fútbol',
          matchDate: DateTime(2026, 9, 30, 19),
          status: status,
          predictionType: PredictionType.win1,
          predictionLabel: 'Choix de l’analyste',
          oddsHome: 1.6,
          oddsDraw: 3.8,
          oddsAway: 4.2,
          oddsRecommended: 1.6,
          confidenceScore: 5,
          isPremium: false,
          homeFormPoints: 9,
          awayFormPoints: 4,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.dark,
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.8)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: MatchCardWidget(match: match),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Borussia Mönchengladbach'), findsOneWidget);
      },
    );
  }

  test(
    'la langue est restaurée et les changements rapides sont persistés dans l’ordre',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings_lang': 'en',
        'access_token': 'unchanged',
      });
      final container = ProviderContainer(
        overrides: [initialLanguageProvider.overrideWithValue('en')],
      );
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).lang, 'en');
      final notifier = container.read(settingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      final first = notifier.setLang('fr');
      final second = notifier.setLang('en');
      await Future.wait([first, second]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_lang'), 'en');
      expect(prefs.getString('access_token'), 'unchanged');
      expect(container.read(localeProvider), const Locale('en'));
      await notifier.setLang('unsupported');
      expect(container.read(settingsProvider).lang, 'fr');
    },
  );

  testWidgets(
    'Paramètres : français → anglais → français sans quitter la page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bioAvailableProvider.overrideWith((ref) async => false),
            appVersionProvider.overrideWith((ref) async => 'v1.0.16'),
          ],
          child: const _SettingsHarness(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paramètres'), findsOneWidget);
      await tester.tap(find.text('Langue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Match alerts'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('settings_lang'),
        'en',
      );
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      expect(find.text('Paramètres'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'anglais accessible avant inscription et écran étroit sans débordement',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: _SettingsHarness(home: OnboardingPage())),
      );
      // Decorative loops keep scheduling frames; wait for finite transitions only.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Français'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Welcome to PronoWin'), findsOneWidget);
      expect(find.text('Daily expert predictions'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var slide = 1; slide < 6; slide++) {
        await tester.tap(find.text('Next'));
        // Let the page transition build its content, then finish its delayed
        // entrance animations, without waiting on the decorative infinite loop.
        for (var frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'onboarding slide $slide',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
