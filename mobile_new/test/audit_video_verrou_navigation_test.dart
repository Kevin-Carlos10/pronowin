import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/prono_share_card.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/parametres/presentation/pages/lock_screen_page.dart';
import 'package:pronowin/features/parametres/presentation/providers/security_provider.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:pronowin/shared/widgets/main_scaffold.dart';

class FakeBio extends LocalAuthentication {
  int calls = 0;
  Completer<bool> result = Completer<bool>();
  @override Future<bool> get canCheckBiometrics async => true;
  @override Future<bool> isDeviceSupported() async => true;
  @override Future<List<BiometricType>> getAvailableBiometrics() async => [BiometricType.face];
  @override Future<bool> stopAuthentication() async => true;
  @override Future<bool> authenticate({required String localizedReason,
    Iterable<dynamic> authMessages = const [], AuthenticationOptions options = const AuthenticationOptions()}) {
    calls++;
    return result.future;
  }
}

void main() {
  testWidgets('deux votes ne deviennent pas une preuve à 100 %', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body:
      barreDeVoteSeule(const PronosticVoteData(agree: 2, disagree: 0, total: 2)))));
    await tester.pumpAndSettle();
    expect(find.text('2 sur 2 d’accord'), findsOneWidget);
    expect(find.text('2 votes'), findsOneWidget);
    expect(find.textContaining('100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('carte partagée compacte avec ligue longue', (tester) async {
    await initializeDateFormatting('fr');
    final match = MatchModel.fromJson({
      'id': 'm1', 'league': 'Ligue des champions féminine européenne', 'league_country': 'Europe',
      'home_team': 'West Ham United', 'away_team': 'Borussia Dortmund',
      'match_date': '2026-10-09T19:00:00Z', 'status': 'upcoming',
      'prediction_type': 'win1', 'prediction_label': 'Domicile',
      'odds_recommended': 1.49, 'odds_home': 1.49, 'odds_draw': 3.4, 'odds_away': 4.2,
      'confidence_score': 5, 'confidence_pct': 81, 'is_premium': false,
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body:
      SingleChildScrollView(child: PronoShareCard(match: match)))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PronoShareCard)).height, lessThan(560));
  });

  testWidgets('Face ID seul : aucun clavier PIN, annulation puis succès', (tester) async {
    SharedPreferences.setMockInitialValues({'security_bio_enabled': true, 'security_pin_enabled': false});
    final bio = FakeBio();
    final container = ProviderContainer(overrides: [localAuthenticationProvider.overrideWithValue(bio)]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).ready;
    final router = GoRouter(initialLocation: '/lock', routes: [
      GoRoute(path: '/lock', builder: (_, _) => const LockScreenPage()),
      GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Contenu privé'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
    await tester.pumpAndSettle();
    expect(bio.calls, 1);
    expect(find.text('1'), findsNothing);
    expect(find.text('Entre ton code PIN'), findsNothing);
    expect(find.text('Contenu privé'), findsNothing);
    bio.result.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Face ID'), findsOneWidget);
    expect(find.text('Contenu privé'), findsNothing);
    bio.result = Completer<bool>();
    await tester.tap(find.text('Face ID'));
    await tester.pump();
    expect(bio.calls, 2);
    bio.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Contenu privé'), findsOneWidget);
  });

  testWidgets('PIN seul : clavier disponible sur petit écran', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'security_bio_enabled': false, 'security_pin_enabled': true});
    final bio = FakeBio();
    final container = ProviderContainer(overrides: [localAuthenticationProvider.overrideWithValue(bio)]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).ready;
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const LockScreenPage())));
    await tester.pumpAndSettle();
    expect(find.text('Entre ton code PIN'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(bio.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('navigation lisible à 320 px et texte agrandi ${theme.brightness}', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: theme, builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.8)), child: child!),
        home: Scaffold(bottomNavigationBar: barreNavigationSeule())));
      await tester.pumpAndSettle();
      for (final label in ['Accueil', 'Pronos', 'Bankroll', 'Tutoriels', 'Compte']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
