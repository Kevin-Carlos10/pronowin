import 'dart:convert';
import 'package:dartz/dartz.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remote;
  final SecureStorageService _storage;

  /// Le jeton de notification de cet appareil, s'il en a un.
  final Future<String?> Function() _jetonAppareil;

  AuthRepositoryImpl(this._remote, this._storage, {Future<String?> Function()? jetonAppareil})
      : _jetonAppareil = jetonAppareil ?? _aucunJeton;

  static Future<String?> _aucunJeton() async => null;

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
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  @override
  Future<bool> sendEmailOtp(String email) => _remote.sendEmailOtp(email);

  @override
  Future<UserEntity> verifyEmailOtp({required String email, required String otp}) async {
    final data = await _remote.verifyEmailOtp(email: email, otp: otp);
    return _saveTokensAndReturn(data);
  }

  /// Le jeton Google est déjà vérifié par le backend : la réponse est
  /// exactement celle de verifyEmailOtp, donc le même enregistrement de session.
  @override
  Future<UserEntity> googleLogin(String idToken) async {
    final data = await _remote.googleLogin(idToken);
    return _saveTokensAndReturn(data);
  }

  @override
  Future<Either<Failure, void>> logout() async {
    // Cette session, et cet appareil. Sans rien dans le corps, le serveur
    // fermait toutes les sessions du compte : se déconnecter d'un téléphone
    // déconnectait les autres. Et le téléphone gardait les notifications
    // privées du compte après la déconnexion (constat I12).
    final refresh = await _storage.read(AppConstants.refreshTokenKey);
    String? appareil;
    try {
      appareil = await _jetonAppareil().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Firebase absent ou muet : la déconnexion ne l'attend pas. Le serveur
      // oubliera ce jeton au premier envoi qui le déclarera mort.
    }
    await _remote.logout(refreshToken: refresh, fcmToken: appareil);
    await _storage.deleteAll();
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
  /// Y a-t-il une session à restaurer ?
  ///
  /// Cette méthode effaçait **tout le stockage** dès que le jeton d'accès était
  /// expiré — jeton de rafraîchissement compris. Or le jeton d'accès vit quinze
  /// minutes et celui de rafraîchissement trente jours : le second existe
  /// précisément pour survivre au premier.
  ///
  /// Conséquence, parfaitement reproductible : fermer l'application, attendre un
  /// quart d'heure, la rouvrir — et se retrouver déconnecté. Après un
  /// redémarrage du téléphone, c'était systématique.
  ///
  /// Un jeton d'accès expiré n'est donc pas un problème, c'est l'état normal.
  /// La seule question est : reste-t-il de quoi en obtenir un nouveau ?
  Future<bool> isLoggedIn() async {
    final refresh = await _storage.read(AppConstants.refreshTokenKey);

    // Il y a de quoi renouveler : l'intercepteur s'en chargera au premier 401.
    if (refresh != null && refresh.isNotEmpty) return true;

    final token = await _storage.read(AppConstants.accessTokenKey);
    if (token == null) return false;

    // Sans jeton de rafraîchissement, un jeton d'accès expiré ne mène nulle
    // part : là, et seulement là, il n'y a rien à conserver.
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
