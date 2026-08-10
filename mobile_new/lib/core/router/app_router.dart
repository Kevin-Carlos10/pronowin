import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/email_auth_page.dart';
import '../../features/auth/presentation/pages/email_otp_page.dart';
import '../../features/auth/presentation/pages/terms_page.dart';
import '../../features/auth/presentation/pages/completer_profil_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/presentation/pages/match_detail_page.dart';
import '../../features/pronostics/domain/entities/match_entity.dart';
import '../../features/tutoriels/presentation/pages/tutorial_detail_page.dart';
import '../../features/tutoriels/domain/entities/tutorial_entity.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/compte/presentation/pages/edit_profile_page.dart';
import '../../features/abonnement/presentation/pages/activer_premium_page.dart';
import '../../features/parametres/presentation/pages/parametres_page.dart';
import '../../features/parametres/presentation/pages/pin_setup_page.dart';
import '../../features/parametres/presentation/pages/lock_screen_page.dart';
import '../../features/parametres/presentation/pages/legal_page.dart';
import '../../features/parrainage/presentation/pages/parrainage_page.dart';
import '../../features/parrainage/presentation/pages/retrait_parrainage_page.dart';
import '../../features/classement/presentation/pages/classement_page.dart';
import '../../features/pronostics/presentation/pages/historique_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/bankroll/presentation/pages/bet_detail_page.dart';
import '../../features/bankroll/presentation/providers/bankroll_provider.dart';
import '../../features/performance/presentation/pages/performance_page.dart';
import '../../features/pronostics/presentation/pages/search_page.dart';
import '../../features/compte/presentation/pages/stats_page.dart';
import '../widgets/in_app_browser_page.dart';
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
    _ref.listen(onboardingDoneProvider,     (_, _) => notifyListeners());
  }

  bool get isLoggedIn => _ref.read(effectiveLoggedInProvider);
}

/// Chemins réservés aux utilisateurs connectés — le reste de l'app
/// (accueil, liste des pronostics, tutoriels, classement...) est
/// consultable librement en mode invité.
const _guestBlockedPrefixes = [
  '/bankroll',
  '/compte/activer-premium',
  '/compte/completer-profil',
  '/compte/edit',
  '/notifications',
  '/parrainage',
  '/performance',
  '/historique',
];

bool _isGuestBlocked(String loc) {
  // Le détail d'un match est ouvert aux invités : six de ses sept onglets ne
  // servent que de la donnée API-Football (score, stats, compositions,
  // blessures, classements, face-à-face), qui n'est pas le produit vendu. Le
  // backend filtre le pronostic premium au lieu de refuser la page, et les
  // actions qui exigent un compte (favori, mise, commentaire) invitent à se
  // connecter au moment du geste.
  return _guestBlockedPrefixes.any((p) => loc == p || loc.startsWith('$p/'));
}

// ─── Provider du routeur ──────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();

  final notifier = _RouterNotifier(ref);

  return GoRouter(
    navigatorKey:      rootNavigatorKey,
    initialLocation:   '/onboarding',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn      = notifier.isLoggedIn;
      final loc           = state.matchedLocation;
      final onAuth        = loc.startsWith('/auth');
      final onLock        = loc == '/lock';
      final onOnboarding  = loc == '/onboarding';
      final onboardingDone = notifier._ref.read(onboardingDoneProvider);

      if (onLock) return null;

      // Onboarding affiché une seule fois au tout premier lancement,
      // indépendamment du statut de connexion.
      if (!onboardingDone && !onOnboarding) return '/onboarding';
      if (onboardingDone && onOnboarding)   return '/home';

      // Un utilisateur déjà connecté n'a rien à faire sur les écrans d'auth.
      if (loggedIn && onAuth) return '/home';

      // L'app est ouverte à tous — seules certaines fonctionnalités
      // (paiement, bankroll, premium, parrainage, notifications, détail
      // d'un pronostic...) exigent une connexion.
      if (!loggedIn && !onAuth && _isGuestBlocked(loc)) {
        return '/auth/email?from=${Uri.encodeComponent(loc)}';
      }

      return null;
    },

    routes: [

      // ── Onboarding (premier lancement) ───────────────────────────────────
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => fadePage(state: s, child: const OnboardingPage()),
      ),

      // ── Auth (fade — pas de contexte précédent) — accès à la demande ──────
      GoRoute(
        path: '/auth/email',
        pageBuilder: (_, s) => fadePage(
          state: s, child: EmailAuthPage(from: s.uri.queryParameters['from'])),
      ),
      GoRoute(
        path: '/auth/email/otp',
        pageBuilder: (_, s) {
          final args = s.extra as Map<String, dynamic>?;
          return slideRightPage(
            state: s,
            child: EmailOtpPage(
              email:     args?['email'] as String? ?? '',
              isNewUser: args?['isNewUser'] as bool? ?? false,
              from:      args?['from']  as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/auth/terms',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: TermsPage(from: s.extra as String?)),
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
        path: '/compte',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 4)),
      ),

      // Tutoriels est l'onglet 3 de MainScaffold — même raison que /bankroll.
      GoRoute(
        path: '/tutoriels',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 3)),
      ),

      // ── Pages listées (slide depuis la droite) ────────────────────────────
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
        path: '/recherche',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const SearchPage()),
      ),
      GoRoute(
        path: '/compte/stats',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const StatsPage()),
      ),
      GoRoute(
        path: '/navigateur',
        pageBuilder: (_, s) {
          final args = s.extra as Map<String, dynamic>?;
          return slideRightPage(
            state: s,
            child: InAppBrowserPage(
              url:   args?['url']   as String? ?? '',
              title: args?['title'] as String? ?? '',
            ),
          );
        },
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

      // Bankroll est l'onglet 2 de MainScaffold : il doit être rendu DANS le
      // scaffold, sinon on y arrive sans barre de navigation (cul-de-sac) —
      // au même titre que /home, /pronostics et /compte.
      GoRoute(
        path: '/bankroll',
        pageBuilder: (_, s) => fadePage(
          state: s, child: const MainScaffold(initialIndex: 2)),
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
          child: CompleterProfilPage(from: s.extra as String?)),
      ),
      GoRoute(
        path: '/performance',
        pageBuilder: (_, s) => scaleUpPage(
          state: s,
          child: const PerformancePage()),
      ),
      // Le détail des filleuls (niveaux 1 et 2) n'existe que sur cette page —
      // l'onglet Parrainage du Compte se limite aux gains et au code. Elle
      // n'avait jamais été déclarée : les deux boutons qui y mènent
      // plantaient sur « no routes for location: /parrainage ».
      GoRoute(
        path: '/parrainage',
        pageBuilder: (_, s) => slideRightPage(
          state: s, child: const ParrainagePage()),
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
