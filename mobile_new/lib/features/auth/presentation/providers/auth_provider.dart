import 'package:flutter_riverpod/flutter_riverpod.dart';
// 1. SUPPRIMEZ l'import 'package:state_notifier/state_notifier.dart'
// flutter_riverpod l'inclut déjà et l'importer deux fois crée un conflit de types.
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/google_auth_service.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/send_otp_usecase.dart';
import '../../domain/usecases/verify_otp_usecase.dart';
import '../../../../core/cache/cache_service.dart';

// ... (Gardez tes classes AuthState et AuthNotifier identiques)

// ─── Dependency Injection ────────────────────────────────────────────────────
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) =>
    AuthRemoteDataSourceImpl(ref.read(dioProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    AuthRepositoryImpl(
      ref.read(authRemoteDataSourceProvider),
      ref.read(secureStorageProvider),
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

  /// Restaure la session à partir du token stocké — appelé une seule fois,
  /// avant le premier frame (voir main.dart), pour éviter qu'un démarrage
  /// à froid (app tuée puis rouverte) soit pris pour une déconnexion.
  Future<void> restoreSession() async {
    final hasValidToken = await _repository.isLoggedIn();
    if (!hasValidToken) { state = AuthInitial(); return; }

    final result = await _repository.getProfile();
    result.fold(
      (failure) {
        // Session confirmée invalide côté serveur → repli invité.
        // Toute autre erreur (réseau, serveur indisponible…) : le token
        // reste valide localement, on ne déconnecte pas — l'UI se
        // resynchronisera dès qu'une requête aboutira.
        if (failure is UnauthorizedFailure) state = AuthInitial();
      },
      (user) => state = AuthAuthenticated(user),
    );
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
        state = AuthAuthenticated(user);
      },
    );
  }

  Future<void> logout() async {
    await _repository.logout();
    // Effacer tout le cache local lié à l'utilisateur
    await CacheService.clearAll();
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

  void reset() => state = AuthInitial();
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
/// explicite ou aucun token) ; tout le reste (y compris AuthUnknown au
/// démarrage à froid) → on consulte le token en stockage sécurisé.
final effectiveLoggedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is AuthAuthenticated) return true;
  if (authState is AuthInitial) return false;
  return ref.watch(isLoggedInProvider).valueOrNull ?? false;
});

