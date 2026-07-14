import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/router/app_router.dart' show appRouterProvider, onboardingDoneProvider;
import 'core/theme/app_theme.dart';
import 'core/widgets/splash_screen.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/services/review_service.dart';
import 'core/services/version_service.dart';
import 'core/services/background_sync_service.dart';
import 'core/storage/secure_storage.dart';
import 'features/notifications/presentation/providers/fcm_service.dart';
import 'features/parametres/presentation/providers/settings_provider.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Garder le splash natif pendant les initialisations async
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await RemoteConfigService.init();
  await BackgroundSyncService.init();

  // Capturer les erreurs Flutter (widgets, layout, etc.)
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Capturer les erreurs async hors Flutter (isolates, futures non catchées)
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final prefs          = await SharedPreferences.getInstance();
  bool  onboardingDone = prefs.getBool('onboarding_done') ?? false;

  // Utilisateur existant : token présent mais onboarding jamais vu
  // → bypasser silencieusement (il connaît déjà l'app)
  if (!onboardingDone) {
    final token = await SecureStorageService().read('access_token');
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

  // Retirer le splash natif → l'app Flutter prend le relais
  FlutterNativeSplash.remove();

  runApp(ProviderScope(
    overrides: [
      onboardingDoneProvider.overrideWith((ref) => onboardingDone),
    ],
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
      BackgroundSyncService.registerPeriodicSync();    // fire-and-forget
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
    final settings = ref.read(settingsProvider);
    if (!settings.pinEnabled && !settings.bioEnabled) {
      _lockChecked = true;
      return;
    }

    final p      = await SharedPreferences.getInstance();
    final hasPin = p.getString('pin_code')?.isNotEmpty ?? false;

    if (hasPin || settings.bioEnabled) {
      _lockChecked = true;
      if (mounted) {
        final router = ref.read(appRouterProvider);
        router.go('/lock');
      }
    } else {
      _lockChecked = true;
    }
  }

  Future<void> _checkLockOnResume() async {
    final settings = ref.read(settingsProvider);
    if (!settings.pinEnabled && !settings.bioEnabled) return;

    final p      = await SharedPreferences.getInstance();
    final hasPin = p.getString('pin_code')?.isNotEmpty ?? false;
    if (!hasPin && !settings.bioEnabled) return;

    if (mounted) {
      final router   = ref.read(appRouterProvider);
      final location = router.routerDelegate.currentConfiguration.last.route.path;
      if (location != '/lock') {
        router.go('/lock');
      }
    }
  }

  Future<void> _checkVersion() async {
    if (!mounted) return;
    await VersionService.check(context);
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
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      builder: (context, child) => MediaQuery(
        data:  MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
    );
  }
}
