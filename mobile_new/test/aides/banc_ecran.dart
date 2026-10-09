import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/connectivity_provider.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/notifications/presentation/providers/notification_service.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/providers/favoris_provider.dart';

/// Banc commun des tests d'écrans complets : vraie police, téléphone réel,
/// texte agrandi, relevé de chaque débordement.
///
/// La police de test de Flutter dessine des carrés de largeur fixe : une
/// mesure de débordement faite avec elle ne vaut rien. Roboto est chargée
/// depuis le SDK qui exécute le test.

/// À appeler dans `setUpAll`.
Future<void> preparerBanc() async {
  await _chargerPolices();
  await initializeDateFormatting('fr');
  await initializeDateFormatting('fr_FR');
  AppStrings.setCurrentLanguage('fr');
}

/// Monte [ecran] dans un téléphone de [largeur] px, texte à [echelle], et
/// renvoie les débordements relevés pendant le rendu et le défilement.
///
/// Les autres erreurs de rendu sont renvoyées à part : un écran qui plante
/// ne doit pas passer pour un écran qui tient.
Future<({List<String> debordements, List<String> autres})> mesurerEcran(
  WidgetTester tester, {
  required Widget ecran,
  required ThemeData theme,
  required double echelle,
  List<Override> surcharges = const [],
  double largeur = 360,
  int defilements = 10,
  /// Appelé une fois l'écran rendu, avant le défilement : pour vérifier ce
  /// qu'il affiche en plus de ce qui déborde.
  void Function()? verifier,
}) async {
  SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true});
  tester.view.physicalSize = Size(largeur * 2, 800 * 2);
  tester.view.devicePixelRatio = 2;
  // Barre d'état et barre de gestes d'un iPhone à encoche (59 et 34 px
  // logiques) : la plus haute courante.
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

  try {
    await tester.pumpWidget(ProviderScope(
      overrides: [...donneesCommunes(), ...surcharges],
      // Un routeur réel : plusieurs écrans lisent leur position dans la pile.
      // Toute autre destination mène à une page vide.
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => ecran)],
          errorBuilder: (_, _) => const Scaffold(),
        ),
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
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    verifier?.call();

    // Tout l'écran, pas seulement le premier tiers.
    final defilable = find.byType(Scrollable);
    for (var i = 0; i < defilements && defilable.evaluate().isNotEmpty; i++) {
      await tester.drag(defilable.first, const Offset(0, -350), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  } finally {
    // Rendu avant toute assertion : un `expect` qui échoue laisserait le
    // gestionnaire détourné, et le banc entier en mauvais état.
    FlutterError.onError = precedent;
  }
  return (
    debordements: debordements.toSet().toList(),
    autres: autres.toSet().toList(),
  );
}

/// Le fichier et la ligne du widget fautif, tels que Flutter les rapporte.
String _origine(FlutterErrorDetails d) {
  final m = RegExp(r'lib[/\\][^\s:]+\.dart:\d+').firstMatch(d.toString());
  return m?.group(0)?.replaceAll(r'\', '/') ?? '?';
}

// ─── Données communes ─────────────────────────────────────────────────────────

/// Un pronostic au format de l'API, avec des noms longs : ce sont eux qui
/// font déborder.
Map<String, dynamic> pronoApi(String id,
        {String status = 'upcoming', Duration dans = const Duration(hours: 13)}) =>
    {
      'id': id,
      'match_id': 'm$id',
      'league': 'UEFA Champions League',
      'league_country': 'Europe',
      'home_team': 'Borussia Mönchengladbach',
      'away_team': 'Real Sociedad de Fútbol',
      'home_team_logo': '',
      'away_team_logo': '',
      'match_date': DateTime.now().add(dans).toUtc().toIso8601String(),
      'status': status,
      'prediction_type': 'win1',
      'prediction_label': 'Domicile ou nul',
      'odds_recommended': 1.62,
      'odds_home': 1.62,
      'odds_draw': 4.2,
      'odds_away': 5.5,
      'confidence_score': 4,
      'is_premium': false,
      'has_pronostic': true,
      'home_form_points': 9,
      'away_form_points': 7,
      'analyst_note': 'Le Borussia reste sur cinq victoires à domicile ; '
          'la Real Sociedad peine loin de ses bases.',
      'home_score': status == 'live' ? 1 : null,
      'away_score': status == 'live' ? 0 : null,
    };

/// Profil complet : sans lui, le paywall renvoie vers « compléter le
/// profil » et c'est cette page-là qu'on mesurerait.
final utilisateurGratuit = UserEntity(
  id: 'u1',
  pseudo: 'Kevin',
  firstName: 'Kevin',
  lastName: 'Zongo',
  birthDate: DateTime(2000, 1, 11),
  phoneNumber: '+22670000000',
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
    state = AuthAuthenticated(utilisateurGratuit);
  }
}

class _AucunFavori extends FavorisNotifier {
  @override
  Future<EtatFavoris> build() async => const EtatFavoris();
}

/// Le serveur du banc : la liste des pronostics et leur détail. Tout le
/// reste répond 404, et l'écran montre alors son état d'erreur — un état
/// qui doit tenir lui aussi.
class _ServeurBanc implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? a) async {
    Object? corps;
    final chemin = o.path;
    if (chemin == '/pronostics') {
      corps = {
        'data': [pronoApi('1', status: 'live', dans: const Duration(minutes: -30)), pronoApi('2'), pronoApi('3')],
        'nextCursor': null,
        'hasMore': false,
      };
    } else if (RegExp(r'^/pronostics/[0-9]+$').hasMatch(chemin)) {
      corps = pronoApi(chemin.split('/').last);
    }
    return ResponseBody.fromString(jsonEncode(corps ?? {'message': 'absent'}), corps == null ? 404 : 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

List<Override> donneesCommunes() => [
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = _ServeurBanc()),
      authProvider.overrideWith(_Connecte.new),
      favorisProvider.overrideWith(_AucunFavori.new),
      isOnlineProvider.overrideWithValue(true),
      unreadCountProvider.overrideWithValue(3),
    ];

// ─── Police réelle ────────────────────────────────────────────────────────────

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
  // Le SDK livre « Roboto-Regular.ttf » : la casse ne compte pas sous Windows,
  // elle compte sous Linux, où les 18 bancs d'écran échouaient en CI.
  final parNom = {
    for (final f in dossier.listSync().whereType<File>())
      f.uri.pathSegments.last.toLowerCase(): f,
  };
  ByteData octets(String f) {
    final fichier = parNom[f.toLowerCase()];
    if (fichier == null) fail('Police $f absente de ${dossier.path}.');
    return ByteData.sublistView(fichier.readAsBytesSync());
  }
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    roboto.addFont(Future.value(octets(f)));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(Future.value(octets('materialicons-regular.otf')))).load();
}
