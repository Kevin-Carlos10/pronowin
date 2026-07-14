import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/user_entity.dart';

abstract class AuthRepository {
  /// Envoie un OTP par SMS au numéro donné.
  Future<Either<Failure, void>> sendOtp(String phoneNumber);

  /// Vérifie l'OTP et retourne l'utilisateur + tokens.
  Future<Either<Failure, UserEntity>> verifyOtp({
    required String phoneNumber,
    required String otp,
  });

  Future<UserEntity> quickRegister({String? phoneNumber, String? email});
  Future<UserEntity> registerEmail({required String email, required String password, required String pseudo});
  Future<UserEntity> loginEmail({required String email, required String password});
  Future<void> sendEmailOtp(String email);
  Future<UserEntity> verifyEmailOtp({required String email, required String otp});

  /// Récupère le profil utilisateur courant.
  Future<Either<Failure, UserEntity>> getProfile();

  /// Déconnecte l'utilisateur (supprime les tokens locaux + appel API).
  Future<Either<Failure, void>> logout();

  /// Supprime définitivement le compte utilisateur.
  Future<Either<Failure, void>> deleteAccount();

  /// Enregistre l'acceptation des CGU et retourne le timestamp.
  Future<Either<Failure, DateTime>> acceptTerms();

  /// Vérifie si l'utilisateur est déjà connecté (token valide).
  Future<bool> isLoggedIn();
}
