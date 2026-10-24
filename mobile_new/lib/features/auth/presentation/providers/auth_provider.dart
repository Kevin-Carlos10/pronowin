import 'package:flutter_riverpod/flutter_riverpod.dart';
// 1. SUPPRIMEZ l'import 'package:state_notifier/state_notifier.dart'
// flutter_riverpod l'inclut déjà et l'importer deux fois crée un conflit de types.
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/apple_auth_service.dart';
import '../../data/datasources/google_auth_service.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/send_otp_usecase.dart';
import '../../domain/usecases/verify_otp_usecase.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../shared/providers/favoris_provider.dart';
import '../../../notifications/presentation/providers/fcm_service.dart';

// ... (Gardez tes classes AuthState et AuthNotifier identiques)

// ─── Dependency Injection ────────────────────────────────────────────────────
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) =>
    AuthRemoteDataSourceImpl(ref.read(dioProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    AuthRepositoryImpl(
      ref.read(authRemoteDataSourceProvider),
      ref.read(secureStorageProvider),
      jetonAppareil: FCMService.getToken,
    ));

final sendOtpUseCaseProvider = Provider<SendOtpUseCase>((ref) =>
    SendOtpUseCase(ref.read(authRepositoryProvider)));

final verifyOtpUseCaseProvider = Provider<VerifyOtpUseCase>((ref) =>
    VerifyOtpUseCase(ref.read(authRepositoryProvider)));

// ─── State ───────────────────────────────────────────────────────────────────
abstract class AuthState {}
/// État initial avant restauration de session au démarrage à froid — distinct
/// de [AuthInitial] pour ne pas être confondu avec une déconnexion explicite.
class AuthUnknown        extends AuthState {}
class AuthInitial        extends AuthState {}
class AuthLoading        extends AuthState {}
class OtpSent            extends AuthState { final String phoneNumber; OtpSent(this.phoneNumber); }
class EmailOtpSent       extends AuthState {
  final String email;
  final bool   isNewUser;
  EmailOtpSent(this.email, {required this.isNewUser});
}
class AuthAuthenticated  extends AuthState { final UserEntity user; AuthAuthenticated(this.user); }
class AuthError          extends AuthState { final String message; AuthError(this.message); }
class TermsAccepted      extends AuthState { final UserEntity user; TermsAccepted(this.user); }

// ─── Notifier ────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final SendOtpUseCase   _sendOtp;
  final VerifyOtpUseCase _verifyOtp;
  final AuthRepository   _repository;

  AuthNotifier(this._sendOtp, this._verifyOtp, this._repository)
      : super(AuthUnknown());

  /// Dernier verdict tranché sur la session : ouverte, fermée, ou inconnu
  /// (`null`, avant la restauration au démarrage).
  ///
  /// Pendant une connexion (`AuthLoading`, `EmailOtpSent`, `AuthError`), le
  /// statut affiché retombait sur [isLoggedInProvider] — une lecture du jeton
  /// gardée en cache. Après une suppression de compte, rien ne la relisait :
  /// elle disait encore « connecté ». Le routeur renvoyait alors vers
  /// l'accueil au milieu de la connexion suivante, et l'app restait sur un
  /// écran gris (vidéo du 2 octobre 2026, « Se connecter avec Apple » juste
  /// après « Supprimer le compte »).
  bool? get sessionOuverte => _sessionOuverte;
  bool? _sessionOuverte;

  @override
  set state(AuthState value) {
    if (value is AuthAuthenticated || value is TermsAccepted) {
      _sessionOuverte = true;
    } else if (value is AuthInitial) {
      _sessionOuverte = false;
    }
    // Chaque profil reçu est gardé : c'est lui qu'on montrera au prochain
    // démarrage, avant la réponse du serveur.
    if (value is AuthAuthenticated) {
      final user = value.user;
      _sansEchec(() => _repository.memoriserProfil(user));
    }
    super.state = value;
  }

  /// Le profil gardé ne fait jamais échouer la session : stockage
  /// indisponible, il manque, voilà tout.
  Future<T?> _sansEchec<T>(Future<T> Function() travail) async {
    try {
      return await travail();
    } catch (_) {
      return null;
    }
  }

  /// Restaure la session à partir du token stocké — appelé une seule fois,
  /// avant le premier frame (voir main.dart), pour éviter qu'un démarrage
  /// à froid (app tuée puis rouverte) soit pris pour une déconnexion.
  ///
  /// « L'application oublie souvent qu'un compte connecté est Premium et
  /// affiche la carte Premium » (signalé le 24 octobre 2026). Le profil
  /// n'était lu qu'ici, une fois : réseau lent ou coupé au démarrage, le
  /// compte restait inconnu jusqu'au prochain lancement — l'app le croyait
  /// gratuit. Désormais le dernier profil connu s'affiche tout de suite, et
  /// le serveur est relu au retour dans l'application, au retour du réseau
  /// et à l'activation du Premium ([resynchroniser]).
  Future<void> restoreSession() async {
    final hasValidToken = await _repository.isLoggedIn();
    if (!hasValidToken) { state = AuthInitial(); return; }

    final memorise = await _sansEchec(_repository.profilMemorise);
    if (memorise != null && state is AuthUnknown) state = AuthAuthenticated(memorise);

    await _relireProfil();
  }

  bool _relectureEnCours = false;
  DateTime? _derniereRelecture;

  /// Relit le profil sur le serveur. Une erreur de réseau ne change rien : le
  /// dernier profil connu reste affiché, et on réessaiera.
  Future<void> _relireProfil() async {
    if (_relectureEnCours) return;
    _relectureEnCours = true;
    try {
      final result = await _repository.getProfile();
      _derniereRelecture = DateTime.now();
      result.fold(
        (failure) {
          // Session confirmée invalide côté serveur → repli invité.
          if (failure is UnauthorizedFailure) {
            state = AuthInitial();
            _sansEchec(_repository.oublierProfil);
          }
        },
        (user) {
          // Une connexion ou une déconnexion a pu passer pendant l'attente :
          // on ne remplace qu'un compte connecté ou encore inconnu.
          if (state is AuthAuthenticated || state is AuthUnknown) state = AuthAuthenticated(user);
        },
      );
    } finally {
      _relectureEnCours = false;
    }
  }

  /// Relit le profil — Premium compris — si une session est ouverte : au
  /// retour dans l'application, au retour du réseau, à une notification
  /// Premium. Une fois par minute au plus, sauf [force].
  Future<void> resynchroniser({bool force = false}) async {
    if (state is! AuthAuthenticated && state is! AuthUnknown) return;
    if (state is AuthUnknown && !await _repository.isLoggedIn()) return;
    final derniere = _derniereRelecture;
    if (!force && derniere != null && DateTime.now().difference(derniere) < const Duration(minutes: 1)) return;
    await _relireProfil();
  }

  Future<void> sendOtp(String phoneNumber) async {
    state = AuthLoading();
    final result = await _sendOtp(phoneNumber);
    result.fold(
      (failure) => state = AuthError(failure.message),
      (_)       => state = OtpSent(phoneNumber),
    );
  }

  Future<void> verifyOtp({required String phoneNumber, required String otp}) async {
    state = AuthLoading();
    final result = await _verifyOtp(phoneNumber: phoneNumber, otp: otp);
    await result.fold(
      (failure) async => state = AuthError(failure.message),
      (user) async {
        // Effacer le cache de l'éventuel ancien compte avant de charger le
        // nouveau — seulement une fois la connexion confirmée réussie.
        await CacheService.clearAll();
        await effacerFavorisLocaux();
        state = AuthAuthenticated(user);
      },
    );
  }

  Future<void> logout() async {
    await _repository.logout();
    // Effacer tout le cache local lié à l'utilisateur
    await CacheService.clearAll();
    await effacerFavorisLocaux();
    state = AuthInitial();
  }

  Future<void> deleteAccount() async {
    final result = await _repository.deleteAccount();
    await result.fold(
      (failure) async => throw Exception(failure.message),
      (_) async {
        // Contrairement à logout(), le cache n'était pas vidé : les jetons
        // restaient sur disque après suppression du compte, et la restauration
        // de session au démarrage repartait dessus. Jamais vu jusqu'ici, cet
        // écran n'ayant jamais été atteignable.
        await CacheService.clearAll();
        await effacerFavorisLocaux();
        state = AuthInitial();
      },
    );
  }

  Future<void> acceptTerms() async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    state = AuthLoading();
    final result = await _repository.acceptTerms();
    result.fold(
      (failure) => state = AuthError(failure.message),
      (dt) {
        // On reconstruit le user avec acceptedTermsAt mis à jour
        final updated = _copyUserWithTerms(current.user, dt);
        state = TermsAccepted(updated);
      },
    );
  }

  UserEntity _copyUserWithTerms(UserEntity u, DateTime dt) => UserEntity(
    id:                   u.id,
    phoneNumber:          u.phoneNumber,
    email:                u.email,
    pseudo:               u.pseudo,
    firstName:            u.firstName,
    lastName:             u.lastName,
    birthDate:            u.birthDate,
    avatarUrl:            u.avatarUrl,
    countryCode:          u.countryCode,
    subscriptionPlan:     u.subscriptionPlan,
    subscriptionExpiresAt:u.subscriptionExpiresAt,
    referralCode:         u.referralCode,
    referralEarnings:     u.referralEarnings,
    createdAt:            u.createdAt,
    acceptedTermsAt:      dt,
    phoneVerified:        u.phoneVerified,
    emailVerified:        u.emailVerified,
  );

  /// Connexion Google. Retourne `false` si l'utilisateur a fermé le sélecteur
  /// de compte — ce n'est pas une erreur, l'écran ne doit rien afficher.
  Future<bool> loginWithGoogle() async {
    state = AuthLoading();
    try {
      final idToken = await GoogleAuthService.obtenirIdToken();
      if (idToken == null) {
        // Annulation : on revient à l'état initial, pas à une erreur.
        state = AuthInitial();
        return false;
      }
      final data = await _repository.googleLogin(idToken);
      await CacheService.clearAll();
      await effacerFavorisLocaux();
      state = AuthAuthenticated(data);
      return true;
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  /// « Se connecter avec Apple ». Même contrat que Google : `false` si la
  /// personne a fermé la fenêtre d'Apple, sans erreur affichée.
  Future<bool> loginWithApple() async {
    state = AuthLoading();
    try {
      final identifiants = await AppleAuthService.obtenir();
      if (identifiants == null) {
        state = AuthInitial();
        return false;
      }
      final data = await _repository.appleLogin(identifiants.versApi());
      await CacheService.clearAll();
      await effacerFavorisLocaux();
      state = AuthAuthenticated(data);
      return true;
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<void> sendEmailOtp(String email) async {
    state = AuthLoading();
    try {
      final isNewUser = await _repository.sendEmailOtp(email);
      state = EmailOtpSent(email, isNewUser: isNewUser);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> verifyEmailOtp({required String email, required String otp}) async {
    state = AuthLoading();
    try {
      final data = await _repository.verifyEmailOtp(email: email, otp: otp);
      await CacheService.clearAll();
      await effacerFavorisLocaux();
      state = AuthAuthenticated(data);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Recharge le profil courant depuis le serveur et met à jour le state
  /// (utilisé après complétion du profil, sans repasser par une connexion).
  Future<void> refreshUser() async {
    final result = await _repository.getProfile();
    result.fold(
      (_)    {},
      (user) => state = AuthAuthenticated(user),
    );
  }

  /// Retour à l'état invité — après un refus de rafraîchissement du jeton.
  ///
  /// Le cache n'était pas vidé ici, contrairement à la déconnexion : après
  /// une session expirée, le compte suivant sur le même téléphone pouvait voir
  /// les données privées du précédent (constat M11).
  void reset() {
    state = AuthInitial();
    CacheService.clearAll();      // sans attendre : l'état invité est immédiat
    effacerFavorisLocaux();
    _sansEchec(_repository.oublierProfil);
  }
}

// Assurez-vous d'utiliser ref.watch au lieu de ref.read à l'intérieur d'un provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(sendOtpUseCaseProvider),
    ref.watch(verifyOtpUseCaseProvider),
    ref.watch(authRepositoryProvider),
  );
});

// Indique si l'user est connecté (pour le router)
final isLoggedInProvider = FutureProvider<bool>((ref) =>
    ref.watch(authRepositoryProvider).isLoggedIn());

/// Statut de connexion synchrone, utilisable partout dans l'UI (mode invité).
/// AuthAuthenticated → connecté ; AuthInitial → invité confirmé (déconnexion
/// explicite ou aucun token) ; pendant une connexion en cours, le dernier
/// verdict tranché ([AuthNotifier.sessionOuverte]) ; au démarrage à froid
/// seulement (AuthUnknown, aucun verdict encore), le token en stockage.
final effectiveLoggedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is AuthAuthenticated) return true;
  if (authState is AuthInitial) return false;
  final tranche = ref.read(authProvider.notifier).sessionOuverte;
  if (tranche != null) return tranche;
  return ref.watch(isLoggedInProvider).valueOrNull ?? false;
});

