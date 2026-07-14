import 'dart:convert';
import 'package:dartz/dartz.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/services/background_sync_service.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remote;
  final SecureStorageService _storage;

  AuthRepositoryImpl(this._remote, this._storage);

  @override
  Future<Either<Failure, void>> sendOtp(String phoneNumber) async {
    try {
      await _remote.sendOtp(phoneNumber);
      return const Right(null);
    } on Failure catch (f) {
      return Left(f);
    }
  }

  @override
  Future<Either<Failure, UserEntity>> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    try {
      final data = await _remote.verifyOtp(phoneNumber: phoneNumber, otp: otp);
      // Sauvegarder les tokens
      final accessToken  = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;
      await _storage.write(AppConstants.accessTokenKey,  accessToken);
      await _storage.write(AppConstants.refreshTokenKey, refreshToken);
      BackgroundSyncService.saveTokenForBackground(accessToken); // fire-and-forget
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      return Right(user);
    } on Failure catch (f) {
      return Left(f);
    }
  }

  @override
  Future<Either<Failure, UserEntity>> getProfile() async {
    try {
      final user = await _remote.getProfile();
      return Right(user);
    } on Failure catch (f) {
      return Left(f);
    }
  }

  Future<UserEntity> _saveTokensAndReturn(Map<String, dynamic> data) async {
    await _storage.write(AppConstants.accessTokenKey,  data['access_token'] as String);
    await _storage.write(AppConstants.refreshTokenKey, data['refresh_token'] as String);
    BackgroundSyncService.saveTokenForBackground(data['access_token'] as String);
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  @override
  Future<UserEntity> quickRegister({String? phoneNumber, String? email}) async {
    final data = await _remote.quickRegister(phoneNumber: phoneNumber, email: email);
    return _saveTokensAndReturn(data);
  }

  @override
  Future<UserEntity> registerEmail({required String email, required String password, required String pseudo}) async {
    final data = await _remote.registerEmail(email: email, password: password, pseudo: pseudo);
    return _saveTokensAndReturn(data);
  }

  @override
  Future<UserEntity> loginEmail({required String email, required String password}) async {
    final data = await _remote.loginEmail(email: email, password: password);
    return _saveTokensAndReturn(data);
  }

  @override
  Future<void> sendEmailOtp(String email) => _remote.sendEmailOtp(email);

  @override
  Future<UserEntity> verifyEmailOtp({required String email, required String otp}) async {
    final data = await _remote.verifyEmailOtp(email: email, otp: otp);
    return _saveTokensAndReturn(data);
  }

  @override
  Future<Either<Failure, void>> logout() async {
    await _remote.logout();
    await _storage.deleteAll();
    BackgroundSyncService.clearTokenForBackground(); // fire-and-forget
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deleteAccount() async {
    try {
      await _remote.deleteAccount();
      await _storage.deleteAll();
      return const Right(null);
    } on Failure catch (f) {
      return Left(f);
    }
  }

  @override
  Future<Either<Failure, DateTime>> acceptTerms() async {
    try {
      final dt = await _remote.acceptTerms();
      return Right(dt);
    } on Failure catch (f) {
      return Left(f);
    }
  }

  @override
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(AppConstants.accessTokenKey);
    if (token == null) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int && DateTime.now().isAfter(DateTime.fromMillisecondsSinceEpoch(exp * 1000))) {
        await _storage.deleteAll();
        return false;
      }
    } catch (_) { /* token malformé → laisser le backend décider */ }
    return true;
  }
}
