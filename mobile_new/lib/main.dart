import 'dart:async';
import 'dart:ui';
import 'package:country_picker/country_picker.dart' show CountryLocalizations;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/constants/app_constants.dart' show AppConstants;
import 'core/router/app_router.dart' show appRouterProvider, onboardingDoneProvider;
import 'core/theme/app_theme.dart';
import 'core/widgets/splash_screen.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/services/review_service.dart';
import 'core/config/distribution_channel.dart';
import 'core/network/dio_client.dart';
import 'core/services/version_service.dart';
import 'core/services/background_sync_service.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/notifications/presentation/providers/fcm_service.dart';
import 'features/parametres/data/pin_store.dart';
import 'features/parametres/presentation/providers/security_provider.dart';
import 'features/parametres/presentation/providers/settings_provider.dart';

/// Force l'arbre de sémantique sur la cible web, pour inspecter l'UI depuis un
/// navigateur (Flutter dessine sur canvas : sans sémantique, il n'y a aucun DOM
/// à lire). Opt-in via --dart-define=FORCE_SEMANTICS=true : les builds
/// Android/iOS ne le passent pas et ne sont donc pas concernés.
const bool _kForceSemantics = bool.fromEnvironment('FORCE_SEMANTICS');

/// Attend [travail], sans laisser le démarrage en dépendre.
///
/// Rend la main au bout de [delai] si le travail n'a pas abouti. Le travail
/// n'est pas annulé : il se poursuit et prendra effet quand il aboutira.
///
/// Les erreurs sont absorbées. Ces initialisations ont toutes un repli —
/// valeurs par défaut, état invité, tâches non programmées — et aucune ne
/// justifie d'empêcher l'application de s'ouvrir.
Future<void> _sansBloquer(
  Future<void> travail,
  String quoi, [
  Duration delai = const Duration(seconds: 3),
]) async {
  try {
    await travail.timeout(delai);
  } on TimeoutException {
    debugPrint('[Démarrage] $quoi dépasse ${delai.inSeconds}s '
               '— on continue sans attendre');
  } catch (e) {
    debugPrint('[Démarrage] $quoi a échoué : $e');
  }
}

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  if (_kForceSemantics) SemanticsBinding.instance.ensureSemantics();
  // Garder le splash natif pendant les initialisations async.
  // Hors web uniquement : le splash natif est une notion Android/iOS, et sur
  // web remove() lève une PlatformException avant runApp — l'app ne démarre pas.
  if (!kIsWeb) FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();

  // ── Rien ne retient le premier écran plus de quelques secondes ────────────
  //
  // Ces initialisations touchent le réseau, et elles étaient attendues sans
  // borne, avant `FlutterNativeSplash.remove()`. Le splash **natif** restait
  // donc affiché tout le temps qu'elles prenaient : pas d'indicateur, pas de
  // message, rien à toucher.
  //
  // Mesuré sur émulateur, connexion lente mais fonctionnelle : **37 secondes**
  // entre le démarrage du moteur Flutter et le premier écran. Réseau coupé, la
  // même application démarrait en quelques secondes — l'échec immédiat rendait
  // la main tout de suite. Autrement dit, le cas le plus fréquent du marché
  // visé était le pire des trois.
  //
  // Aucune de ces deux initialisations n'est nécessaire au premier écran :
  //
  //   * `RemoteConfigService` a déjà ses valeurs par défaut en mémoire, et
  //     elles ne sont lues qu'au contrôle de version, plus tard ;
  //   * `BackgroundSyncService` programme des tâches de fond — par définition,
  //     rien que l'utilisateur attend maintenant.
  //
  // On leur laisse un délai court, puis on avance. Elles continuent en
  // arrière-plan : le délai écourte l'attente, il n'annule pas le travail.
  await _sansBloquer(RemoteConfigService.init(), 'RemoteConfig');
  await _sansBloquer(BackgroundSyncService.init(), 'BackgroundSync');

  // Capturer les erreurs Flutter (widgets, layout, etc.)
  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Capturer les erreurs async hors Flutter (isolates, futures non catchées)
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  final prefs          = await SharedPreferences.getInstance();
  bool  onboardingDone = prefs.getBool('onboarding_done') ?? false;

  // Utilisateur existant : token présent mais onboarding jamais vu
  // → bypasser silencieusement (il connaît déjà l'app)
  if (!onboardingDone) {
    // La clé venait d'un littéral recopié ici. Le reste de l'application lit
    // `AppConstants.accessTokenKey` : la renommer aurait laissé cette ligne
    // chercher une clé qui n'existe plus, et chaque utilisateur déjà installé
    // aurait revu l'onboarding — sans erreur nulle part.
    final token = await SecureStorageService().read(AppConstants.accessTokenKey);
    if (token != null && token.isNotEmpty) {
      onboardingDone = true;
      await prefs.setBool('onboarding_done', true);
    }
  }

  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('en_US', null);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Créer le container tôt pour restaurer la session (token stocké) AVANT
  // le premier frame — évite qu'un démarrage à froid (app tuée puis
  // rouverte) affiche l'écran invité alors qu'une session valide existe.
  final container = ProviderContainer(
    overrides: [
      onboardingDoneProvider.overrideWith((ref) => onboardingDone),
    ],
  );
  // La restauration de session est attendue à dessein : sans elle, un
  // démarrage à froid affiche brièvement l'écran invité alors qu'une session
  // valide existe. Mais elle interroge le serveur, et l'attendre sans borne
  // rendait ce défaut d'affichage pire que ce qu'il évitait.
  //
  // Quatre secondes : au-delà, un bref passage par l'état invité coûte moins
  // qu'un splash immobile. La session se rétablit dès que la réponse arrive.
  await _sansBloquer(
    container.read(authProvider.notifier).restoreSession(),
    'restoreSession',
    const Duration(seconds: 4),
  );

  // Retirer le splash natif → l'app Flutter prend le relais
  if (!kIsWeb) FlutterNativeSplash.remove();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const SplashScreen(child: PronoWinApp()),
  ));
}

class PronoWinApp extends ConsumerStatefulWidget {
  const PronoWinApp({super.key});
  @override
  ConsumerState<PronoWinApp> createState() => _PronoWinAppState();
}

class _PronoWinAppState extends ConsumerState<PronoWinApp>
    with WidgetsBindingObserver {

  bool      _lockChecked  = false;
  DateTime? _pausedAt;    // Moment où l'app est passée en background

  // Durée minimale en background avant de verrouiller (30 secondes)
  static const _lockDelay = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initFCM();
      await _checkLockOnStart();
      await _checkVersion();
      ReviewService.onSessionStart();                  // fire-and-forget
      // La synchronisation de fond est retirée : on annule celle qu'avaient
      // enregistrée les versions précédentes (constats M4, M8).
      BackgroundSyncService.retirer();                 // fire-and-forget
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // App vraiment en background → enregistrer l'heure
        _pausedAt = DateTime.now();
        debugPrint('[Lifecycle] App mise en pause à $_pausedAt');
        break;

      case AppLifecycleState.resumed:
        if (!_lockChecked || _pausedAt == null) return;

        // Calculer combien de temps l'app était en background
        final elapsed = DateTime.now().difference(_pausedAt!);
        debugPrint('[Lifecycle] App revenue — absente depuis ${elapsed.inSeconds}s');

        // Ne verrouiller que si absente depuis plus de 30 secondes
        if (elapsed >= _lockDelay) {
          _checkLockOnResume();
        }
        _pausedAt = null;
        break;

      case AppLifecycleState.inactive:
        // Clavier, dialogue système, notification — IGNORER
        // Ne pas verrouiller ici
        break;

      default:
        break;
    }
  }

  Future<void> _checkLockOnStart() async {
    final verrouiller = await doitVerrouiller(
      settings: ref.read(settingsProvider),
      pinStore: ref.read(pinStoreProvider));
    _lockChecked = true;
    if (verrouiller && mounted) {
      ref.read(appRouterProvider).go('/lock');
    }
  }

  Future<void> _checkLockOnResume() async {
    final verrouiller = await doitVerrouiller(
      settings: ref.read(settingsProvider),
      pinStore: ref.read(pinStoreProvider));
    if (!verrouiller || !mounted) return;

    final router   = ref.read(appRouterProvider);
    final location = router.routerDelegate.currentConfiguration.last.route.path;
    if (location != '/lock') {
      router.go('/lock');
    }
  }

  Future<void> _checkVersion() async {
    if (!mounted) return;
    // Le canal décide de la destination : fiche du store, ou téléchargement
    // de l'APK. Un build direct renvoyé vers Play tomberait sur une fiche qui
    // n'héberge pas sa version.
    // Le contexte n'est volontairement plus transmis : celui de cet État se
    // situe au-dessus du `MaterialApp.router` qu'il construit, donc au-dessus
    // de tout `Navigator`. Le service résout lui-même la clé du navigateur
    // racine, seul contexte d'où une fenêtre peut s'ouvrir.
    await VersionService.check(
      estStore: ref.read(isStoreBuildProvider),
      dio:      ref.read(dioProvider),
    );
  }

  Future<void> _initFCM() async {
    try {
      await FCMService.init(ref: ref);
      // Consommer un éventuel deep link d'app-tuée (attend frame suivante)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FCMService.consumePendingDeepLink();
      });
    } catch (e) {
      debugPrint('[FCM] Init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router    = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale    = ref.watch(localeProvider);

    return MaterialApp.router(
      title:       'PronoWin',
      theme:       AppTheme.light,
      darkTheme:   AppTheme.dark,
      themeMode:   themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // Sans ce délégué, les noms de pays du sélecteur d'indicatif restent
        // en anglais (« Senegal », « Algeria ») au milieu d'une app française.
        CountryLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      // Taille de texte : bornée, pas ignorée.
      //
      // C'était `TextScaler.noScaling` — le réglage système n'avait donc
      // **aucun** effet. Un utilisateur qui a agrandi le texte de son téléphone
      // parce qu'il lit mal retrouvait ici les tailles d'origine, sans recours.
      //
      // La borne haute est **mesurée**, pas estimée : `echelle_texte_
      // debordement_test.dart` rend la carte de match — le widget le plus
      // répété de l'application — à trois largeurs réelles, dont 320 px. Elle
      // tient jusqu'à 1,8 partout ; à 2,0 elle cède sur 320 px (mesure du
      // 24 septembre 2026, constat M13 : le plafond de 1,5 ignorait une
      // partie du réglage d'accessibilité du téléphone).
      //
      // La première version de cette borne valait 1,3, choisie à l'estime.
      // Deux débordements corrigés depuis — un nom de ligue et un libellé sans
      // contrainte — ont dégagé les deux crans supplémentaires.
      builder: (context, child) {
        final systeme = MediaQuery.textScalerOf(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: systeme.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.8),
          ),
          child: child!,
        );
      },
    );
  }
}
