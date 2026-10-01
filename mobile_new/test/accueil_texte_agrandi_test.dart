import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/connectivity_provider.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';
import 'package:pronowin/features/accueil/presentation/providers/accueil_provider.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';

/// L'accueil entier, à 360 px, texte agrandi à 180 %, dans les deux thèmes.
///
/// ── Ce qui débordait ──────────────────────────────────────────────────────
///
/// Les bancs de débordement existants rendaient des composants isolés : la
/// carte de match, les widgets partagés. L'accueil, lui, n'était jamais
/// assemblé. À 360 px et 180 % — le plafond que `main.dart` laisse au réglage
/// système — deux lignes y débordaient :
///
///   · « Plan Gratuit · Passer Premium ✨ », de 13 px ;
///   · la date et le badge du prochain match, de 44 px.
///
/// ── Le banc ───────────────────────────────────────────────────────────────
///
/// Vraie police (Roboto du SDK : la police de test de Flutter dessine des
/// carrés de largeur fixe, qui ne mesurent rien), données locales, compte
/// gratuit connecté — c'est lui qui voit le plus de contenu. Chaque débordement
/// signalé par Flutter pendant le rendu et le défilement est relevé.
void main() {
  setUpAll(() async {
    await _chargerPolices();
    await initializeDateFormatting('fr');
    await initializeDateFormatting('fr_FR');
    AppStrings.setCurrentLanguage('fr');
  });

  for (final (nomTheme, theme) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
    for (final echelle in [1.0, 1.8]) {
      testWidgets('accueil · $nomTheme · texte ${(echelle * 100).round()} % · 360 px',
          (tester) async {
        SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true});
        tester.view.physicalSize = const Size(360 * 2, 800 * 2);
        tester.view.devicePixelRatio = 2;
        // Barre d'état et barre de gestes d'un iPhone à encoche (59 et 34 px
        // logiques) : la plus haute courante, celle qui passait sous la
        // marge de 48 px écrite en dur dans l'en-tête.
        tester.view.padding = const FakeViewPadding(top: 59 * 2, bottom: 34 * 2);
        addTearDown(tester.view.reset);

        final debordements = <String>[];
        final autres = <String>[];
        final precedent = FlutterError.onError;
        FlutterError.onError = (d) {
          final texte = d.exceptionAsString();
          (texte.contains('overflowed') ? debordements : autres)
              .add('${texte.split('\n').first} ← ${_origine(d)}');
        };

        await tester.pumpWidget(ProviderScope(
          overrides: _donnees(),
          child: MaterialApp(
            theme: theme,
            locale: const Locale('fr'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
              child: child!,
            ),
            home: const AccueilPage(),
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Toute la page, pas seulement le premier écran.
        final defilement = find.byType(Scrollable).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(defilement, const Offset(0, -350));
          await tester.pump(const Duration(milliseconds: 200));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(minutes: 1));
        // Rendu avant toute assertion : un `expect` qui échoue laisserait le
        // gestionnaire détourné, et le banc entier en mauvais état.
        FlutterError.onError = precedent;

        expect(autres.toSet().toList(), isEmpty,
            reason: 'erreurs de rendu autres que des débordements');
        expect(debordements.toSet().toList(), isEmpty);
      });
    }
  }
}

/// Le fichier et la ligne du widget fautif, tels que Flutter les rapporte.
String _origine(FlutterErrorDetails d) {
  final m = RegExp(r'lib[/\\][^\s:]+\.dart:\d+').firstMatch(d.toString());
  return m?.group(0)?.replaceAll(r'\', '/') ?? '?';
}

// ─── Données ──────────────────────────────────────────────────────────────────

/// Des noms longs : ce sont eux qui font déborder.
Map<String, dynamic> _prono(String id, {String status = 'upcoming', Duration dans = const Duration(hours: 13)}) => {
      'id': id,
      'match_id': 'm$id',
      'league': 'UEFA Champions League',
      'home_team': 'Borussia Mönchengladbach',
      'away_team': 'Real Sociedad de Fútbol',
      'home_team_logo': '',
      'away_team_logo': '',
      'match_date': DateTime.now().add(dans).toUtc().toIso8601String(),
      'status': status,
      'prediction_label': 'Domicile ou nul',
      'odds_recommended': 1.62,
      'confidence_score': 4,
      'is_premium': false,
      'home_form_points': 9,
      'away_form_points': 7,
      'home_score': status == 'live' ? 1 : null,
      'away_score': status == 'live' ? 0 : null,
    };

final _utilisateur = UserEntity(
  id: 'u1',
  pseudo: 'Kevin',
  firstName: 'Kevin',
  countryCode: 'BF',
  subscriptionPlan: SubscriptionPlan.free,
  referralCode: '1A639B',
  referralEarnings: 0,
  createdAt: DateTime(2026, 8, 16),
);

class _Connecte extends AuthNotifier {
  _Connecte(Ref ref)
      : super(ref.watch(sendOtpUseCaseProvider), ref.watch(verifyOtpUseCaseProvider),
            ref.watch(authRepositoryProvider)) {
    state = AuthAuthenticated(_utilisateur);
  }
}

class _AucunFavori extends FavorisNotifier {
  @override
  Future<EtatFavoris> build() async => const EtatFavoris();
}

/// Aucune requête ne doit partir : tout ce que l'accueil lit est fourni ici.
class _HorsLigne implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async =>
      ResponseBody.fromString('{}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

List<Override> _donnees() => [
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = _HorsLigne()),
      authProvider.overrideWith(_Connecte.new),
      favorisProvider.overrideWith(_AucunFavori.new),
      isOnlineProvider.overrideWithValue(true),
      unreadCountProvider.overrideWithValue(3),
      lastPronosSyncProvider.overrideWithValue(null),
      isServingFromCacheProvider.overrideWithValue(false),
      currentSubscriptionProvider.overrideWith((ref) async => {'plan': 'free', 'days_left': 0}),
      pronosticsJourProvider.overrideWith((ref) async => [
            _prono('1', status: 'live', dans: const Duration(minutes: -30)),
            _prono('2'),
            _prono('3', dans: const Duration(hours: 3)),
          ]),
      nextPronosticProvider.overrideWith((ref) async => _prono('2')),
      statsJourProvider.overrideWith((ref) async =>
          {'winRate': 64, 'streak': 3, 'upcoming': 5, 'publishedToday': 6, 'totalFinished': 28}),
      performance30Provider.overrideWith((ref) async => {'total': 30, 'wins': 18, 'roi': 12.4}),
      hierProvider.overrideWith((ref) async => const []),
      actualitesProvider.overrideWith((ref) async => const []),
      favoritesListProvider.overrideWith((ref) async => const []),
      bankrollProvider.overrideWith((ref) async => BankrollData(
            id: 'b', totalBudget: 1000000, currentBalance: 997000, currency: 'XOF',
            bets: const [],
          )),
    ];

// ─── Police réelle ────────────────────────────────────────────────────────────

/// Roboto, depuis le SDK Flutter qui exécute le test.
///
/// `flutter_tester` vit dans `<sdk>/bin/cache/artifacts/engine/<plateforme>/` ;
/// les polices Material dans `<sdk>/bin/cache/artifacts/material_fonts/`.
Future<void> _chargerPolices() async {
  final racines = [
    if (Platform.environment['FLUTTER_ROOT'] case final r?)
      '$r/bin/cache/artifacts/material_fonts',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  final dossier = racines.map(Directory.new).where((d) => d.existsSync()).firstOrNull;
  if (dossier == null) {
    fail('Polices Material introuvables (cherchées dans $racines) : '
        'sans elles, la mesure ne vaut rien.');
  }
  ByteData octets(String f) =>
      ByteData.sublistView(File('${dossier.path}/$f').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    roboto.addFont(Future.value(octets(f)));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(Future.value(octets('materialicons-regular.otf')))).load();
}
