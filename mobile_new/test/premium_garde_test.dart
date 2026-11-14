import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/network/failures.dart';
import 'package:pronowin/features/auth/data/models/user_model.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/auth/domain/repositories/auth_repository.dart';
import 'package:pronowin/features/auth/domain/usecases/send_otp_usecase.dart';
import 'package:pronowin/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « L'application oublie souvent qu'un compte connecté est Premium et
/// affiche la carte Premium » (24 octobre 2026).
///
/// Le profil n'était lu qu'au démarrage, une fois : réseau lent ou coupé à ce
/// moment-là, le compte restait inconnu jusqu'au lancement suivant, et l'app
/// le croyait gratuit. Un Premium accordé pendant la session (preuve validée,
/// Mobile Money) n'apparaissait, lui, qu'au redémarrage.
UserEntity _compte({required bool premium}) => UserEntity(
  id: 'u7', pseudo: 'Awa', email: 'awa@example.com', firstName: 'Awa', lastName: 'Traoré',
  birthDate: DateTime(1998, 3, 4), countryCode: 'CI',
  subscriptionPlan: premium ? SubscriptionPlan.premium : SubscriptionPlan.free,
  subscriptionExpiresAt: premium ? DateTime.now().add(const Duration(days: 20)) : null,
  referralCode: 'AWA7', referralEarnings: 1500, createdAt: DateTime(2026, 9, 1),
  acceptedTermsAt: DateTime(2026, 9, 1, 10), phoneVerified: false, emailVerified: true,
);

class _Depot implements AuthRepository {
  UserEntity? garde;
  /// La réponse du serveur à la lecture du profil.
  Future<Either<Failure, UserEntity>> Function() reponse =
      () async => const Left(NetworkFailure());
  int lectures = 0;

  @override
  Future<Either<Failure, UserEntity>> getProfile() { lectures++; return reponse(); }
  @override
  Future<bool> isLoggedIn() async => true;
  @override
  Future<void> memoriserProfil(UserEntity user) async => garde = user;
  @override
  Future<UserEntity?> profilMemorise() async => garde;
  @override
  Future<void> oublierProfil() async => garde = null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Depot depot;
  late ProviderContainer conteneur;
  late AuthNotifier auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    depot = _Depot();
    conteneur = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthNotifier(SendOtpUseCase(depot), VerifyOtpUseCase(depot), depot)),
    ]);
    auth = conteneur.read(authProvider.notifier);
  });
  tearDown(() => conteneur.dispose());

  bool premium() {
    final s = conteneur.read(authProvider);
    return s is AuthAuthenticated && s.user.isPremium;
  }

  test('démarrage sans réseau : le dernier profil connu, Premium compris', () async {
    depot.garde = _compte(premium: true);
    await auth.restoreSession();
    expect(conteneur.read(authProvider), isA<AuthAuthenticated>());
    expect(premium(), isTrue);
  });

  test('réseau lent : le profil gardé s\'affiche avant la réponse, puis le serveur l\'emporte', () async {
    depot.garde = _compte(premium: false);
    final serveur = Completer<Either<Failure, UserEntity>>();
    depot.reponse = () => serveur.future;
    final restauration = auth.restoreSession();
    await Future<void>.delayed(Duration.zero);
    expect(conteneur.read(authProvider), isA<AuthAuthenticated>());
    expect(premium(), isFalse);
    // Le Premium a été accordé depuis : le serveur le dit.
    serveur.complete(Right(_compte(premium: true)));
    await restauration;
    expect(premium(), isTrue);
    expect(depot.garde!.isPremium, isTrue, reason: 'le profil gardé suit le serveur');
  });

  test('ni profil gardé ni réseau : compte inconnu, puis relu au retour du réseau', () async {
    await auth.restoreSession();
    expect(conteneur.read(authProvider), isA<AuthUnknown>());
    depot.reponse = () async => Right(_compte(premium: true));
    await auth.resynchroniser(force: true);
    expect(premium(), isTrue);
  });

  test('Premium accordé pendant la session : relu au retour dans l\'app — une fois par minute au plus', () async {
    depot.reponse = () async => Right(_compte(premium: false));
    await auth.restoreSession();
    expect(premium(), isFalse);
    depot.reponse = () async => Right(_compte(premium: true));
    await auth.resynchroniser();   // la lecture du démarrage date de moins d'une minute
    expect(depot.lectures, 1);
    expect(premium(), isFalse);
    // « Bienvenue Premium ! » : relu sans attendre.
    await auth.resynchroniser(force: true);
    expect(depot.lectures, 2);
    expect(premium(), isTrue);
  });

  test('une erreur de réseau en cours de session ne retire pas le Premium', () async {
    depot.reponse = () async => Right(_compte(premium: true));
    await auth.restoreSession();
    depot.reponse = () async => const Left(NetworkFailure());
    await auth.resynchroniser(force: true);
    expect(premium(), isTrue);
  });

  test('session refusée par le serveur : invité, et le profil gardé oublié', () async {
    depot.garde = _compte(premium: true);
    depot.reponse = () async => const Left(UnauthorizedFailure());
    await auth.restoreSession();
    expect(conteneur.read(authProvider), isA<AuthInitial>());
    expect(depot.garde, isNull);
  });

  test('après une déconnexion, une relecture ne rouvre pas la session', () async {
    depot.reponse = () async => Right(_compte(premium: true));
    await auth.restoreSession();
    auth.reset();
    await auth.resynchroniser(force: true);
    expect(conteneur.read(authProvider), isA<AuthInitial>());
    expect(depot.garde, isNull);
  });

  test('le profil gardé se relit à l\'identique', () {
    final avant = _compte(premium: true);
    final apres = UserModel.fromJson(profilVersJson(avant));
    expect(apres.props, avant.props);
    expect(apres.isPremium, isTrue);
    expect(apres.subscriptionExpiresAt, avant.subscriptionExpiresAt);
    expect([apres.email, apres.firstName, apres.lastName, apres.birthDate, apres.referralEarnings,
        apres.acceptedTermsAt, apres.emailVerified, apres.createdAt],
      [avant.email, avant.firstName, avant.lastName, avant.birthDate, avant.referralEarnings,
        avant.acceptedTermsAt, avant.emailVerified, avant.createdAt]);
  });
}
