import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/phone_page.dart';
import '../../features/auth/presentation/pages/otp_page.dart';
import '../../features/auth/presentation/pages/terms_page.dart';
import '../../features/auth/presentation/pages/completer_profil_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/presentation/pages/match_detail_page.dart';
import '../../features/pronostics/domain/entities/match_entity.dart';
import '../../features/tutoriels/presentation/pages/tutorial_detail_page.dart';
import '../../features/tutoriels/presentation/pages/tutoriels_page.dart';
import '../../features/tutoriels/domain/entities/tutorial_entity.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/compte/presentation/pages/edit_profile_page.dart';
import '../../features/abonnement/presentation/pages/activer_premium_page.dart';
import '../../features/parametres/presentation/pages/parametres_page.dart';
import '../../features/parametres/presentation/pages/pin_setup_page.dart';
import '../../features/parametres/presentation/pages/lock_screen_page.dart';
import '../../features/parametres/presentation/pages/legal_page.dart';
import '../../features/parrainage/presentation/pages/retrait_parrainage_page.dart';
import '../../features/classement/presentation/pages/classement_page.dart';
import '../../features/pronostics/presentation/pages/historique_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/bankroll/presentation/pages/bankroll_page.dart';
import '../../features/depot_retrait/presentation/pages/depot_retrait_page.dart';
import '../../features/bankroll/presentation/pages/bet_detail_page.dart';
import '../../features/bankroll/presentation/providers/bankroll_provider.dart';
import '../../shared/widgets/main_scaffold.dart';
import 'navigation_keys.dart';
import 'page_transitions.dart';
// Provider synchrone — initialisé dans main.dart avant runApp
final onboardingDoneProvider = StateProvider<bool>((ref) => false);

// ─── RouterNotifier ───────────────────────────────────────────────────────────
class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider,   (_, _) => notifyListeners());
    _ref.listen(isLoggedInProvider,         (_, _) => notifyListeners());
  }

  bool get isLoggedIn {
    final authState = _ref.read(authProvider);
    // Si le notifier a explicitement déconnecté → jamais logué, peu importe le storage
    if (authState is AuthInitial) return false;
    if (authState is AuthAuthenticated) return true;
    // États intermédiaires (Loading, OtpSent, Error) → on consulte le storage
    final stored = _ref.read(isLoggedInProvider).valueOrNull ?? false;
    return stored;
  }
}

// ─── Provider du routeur ──────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();

  final notifier = _RouterNotifier(ref);

  return GoRouter(
    navigatorKey:      rootNavigatorKey,
    initialLocation:   '/auth/phone',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = notifier.isLoggedIn;
      final loc      = state.matchedLocation;
      final onAuth       = loc.startsWith('/auth');
      final onLock       = loc == '/lock';
      final onOnboarding = loc == '/onboarding';

      if (onLock)               return null;
      if (!loggedIn && !onAuth) return '/auth/phone';
      if (loggedIn && onAuth) {
        final done = notifier._ref.read(onboardingDoneProvider);
        return done ? '/home' : '/onboarding';
      }
      if (loggedIn && onOnboarding) return null;
      return null;
    },

    routes: [

      // ── Onboarding (premier lancement) ───────────────────────────────────
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => fadePage(state: s, child: const OnboardingPage()),
      ),

      // ── Auth (fade — pas de contexte précédent) ───────────────────────────
      GoRoute(
        path: '/auth/phone',
        pageBuilder: (_, s) => fadePage(state: s, child: const PhonePage()),
      ),
      GoRoute(
        path: '/auth/otp',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: OtpPage(phoneNumber: s.extra as String)),
      ),
      GoRoute(
        path: '/auth/terms',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const TermsPage()),
      ),

      // ── Lock screen (fade rapide) ──────────────────────────────────────────
      GoRoute(
        path: '/lock',
        pageBuilder: (_, s) => fadePage(
          state: s,
          child: LockScreenPage(redirectTo: (s.extra as String?) ?? '/home')),
      ),

      // ── Navigation principale (fade — tabs, pas de slide) ─────────────────
      GoRoute(
        path: '/home',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 0)),
      ),
      GoRoute(
        path: '/pronostics',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 1)),
      ),
      GoRoute(
        path: '/depot-retrait',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const DepotRetraitPage()),
      ),
      GoRoute(
        path: '/compte',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 4)),
      ),

      // ── Pages listées (slide depuis la droite) ────────────────────────────
      GoRoute(
        path: '/tutoriels',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const TutorielsPage()),
      ),
      GoRoute(
        path: '/classement',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const ClassementPage()),
      ),
      GoRoute(
        path: '/historique',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const HistoriquePage()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const NotificationsPage()),
      ),
      GoRoute(
        path: '/compte/edit',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const EditProfilePage()),
      ),
      GoRoute(
        path: '/parametres',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const ParametresPage()),
      ),
      GoRoute(
        path: '/parametres/pin',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const PinSetupPage()),
      ),
      GoRoute(
        path: '/parametres/cgu',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const LegalPage(type: LegalType.cgu)),
      ),
      GoRoute(
        path: '/parametres/confidentialite',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const LegalPage(type: LegalType.confidentialite)),
      ),
      GoRoute(
        path: '/parametres/jeu-responsable',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const LegalPage(type: LegalType.jeuResponsable)),
      ),

      GoRoute(
        path: '/bankroll',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const BankrollPage()),
      ),
      GoRoute(
        path: '/bankroll/bet/:id',
        pageBuilder: (_, s) => slideRightPage(
          state: s,
          child: BetDetailPage(bet: s.extra as BankrollBet)),
      ),

      // ── Détails (slide up modal + Hero) ────────────────────────────────────
      GoRoute(
        path: '/pronostics/:id',
        pageBuilder: (_, s) => slideUpPage(
          state: s,
          child: MatchDetailPage(
            matchId:   s.pathParameters['id']!,
            preloaded: s.extra as MatchEntity?)),
      ),
      GoRoute(
        path: '/tutoriels/:id',
        pageBuilder: (_, s) => slideUpPage(
          state: s,
          child: TutorialDetailPage(
            tutorialId: s.pathParameters['id']!,
            preloaded:  s.extra as TutorialEntity?)),
      ),

      // ── Modales premium / paiement (scale up) ─────────────────────────────
      GoRoute(
        path: '/compte/activer-premium',
        pageBuilder: (_, s) => scaleUpPage(
          state: s,
          child: ActiverPremiumPage(
            subData: s.extra as Map<String, dynamic>?)),
      ),
      GoRoute(
        path: '/compte/completer-profil',
        pageBuilder: (_, s) => scaleUpPage(
          state: s,
          child: const CompleterProfilPage()),
      ),
      GoRoute(
        path: '/parrainage/retrait',
        pageBuilder: (_, s) => scaleUpPage(
          state: s,
          child: RetraitParrainagePage(
            data: s.extra as Map<String, dynamic>?)),
      ),
    ],

    errorBuilder: (_, s) => Scaffold(
      body: Center(child: Text('Page introuvable : ${s.error}'))),
  );
});
