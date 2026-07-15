import 'package:flutter_riverpod/flutter_riverpod.dart';
// 1. SUPPRIMEZ l'import 'package:state_notifier/state_notifier.dart' 
// flutter_riverpod l'inclut déjà et l'importer deux fois crée un conflit de types.
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/auth_remote_datasource.dart';
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
class AuthInitial        extends AuthState {}
class AuthLoading        extends AuthState {}
class OtpSent            extends AuthState { final String phoneNumber; OtpSent(this.phoneNumber); }
class EmailOtpSent       extends AuthState { final String email; EmailOtpSent(this.email); }
class AuthAuthenticated  extends AuthState { final UserEntity user; AuthAuthenticated(this.user); }
class AuthError          extends AuthState { final String message; AuthError(this.message); }
class TermsAccepted      extends AuthState { final UserEntity user; TermsAccepted(this.user); }

// ─── Notifier ────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final SendOtpUseCase   _sendOtp;
  final VerifyOtpUseCase _verifyOtp;
  final AuthRepository   _repository;

  AuthNotifier(this._sendOtp, this._verifyOtp, this._repository)
      : super(AuthInitial());

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
    // Effacer le cache de l'éventuel ancien compte avant de charger le nouveau
    await CacheService.clearAll();
    final result = await _verifyOtp(phoneNumber: phoneNumber, otp: otp);
    result.fold(
      (failure) => state = AuthError(failure.message),
      (user)    => state = AuthAuthenticated(user),
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
    result.fold(
      (failure) => throw Exception(failure.message),
      (_)       => state = AuthInitial(),
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
    avatarUrl:            u.avatarUrl,
    countryCode:          u.countryCode,
    subscriptionPlan:     u.subscriptionPlan,
    subscriptionExpiresAt:u.subscriptionExpiresAt,
    referralCode:         u.referralCode,
    referralEarnings:     u.referralEarnings,
    createdAt:            u.createdAt,
    acceptedTermsAt:      dt,
  );

  Future<void> quickRegister({String? phoneNumber, String? email}) async {
    state = AuthLoading();
    await CacheService.clearAll();
    try {
      final data = await _repository.quickRegister(phoneNumber: phoneNumber, email: email);
      state = AuthAuthenticated(data);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> loginWithEmail({required String email, required String password}) async {
    state = AuthLoading();
    await CacheService.clearAll();
    try {
      final data = await _repository.loginEmail(email: email, password: password);
      state = AuthAuthenticated(data);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> registerWithEmail({required String email, required String password, required String pseudo}) async {
    state = AuthLoading();
    await CacheService.clearAll();
    try {
      final data = await _repository.registerEmail(email: email, password: password, pseudo: pseudo);
      state = AuthAuthenticated(data);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> sendEmailOtp(String email) async {
    state = AuthLoading();
    try {
      await _repository.sendEmailOtp(email);
      state = EmailOtpSent(email);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> verifyEmailOtp({required String email, required String otp}) async {
    state = AuthLoading();
    await CacheService.clearAll();
    try {
      final data = await _repository.verifyEmailOtp(email: email, otp: otp);
      state = AuthAuthenticated(data);
    } catch (e) {
      state = AuthError(e.toString().replaceFirst('Exception: ', ''));
    }
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

