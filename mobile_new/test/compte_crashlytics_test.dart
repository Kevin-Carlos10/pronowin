import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/network/failures.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/auth/domain/repositories/auth_repository.dart';
import 'package:pronowin/features/auth/domain/usecases/send_otp_usecase.dart';
import 'package:pronowin/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';
import 'package:pronowin/features/auth/presentation/providers/compte_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les rapports de plantage suivent le compte connecté.
///
/// La politique de confidentialité, le site et la fiche App Store le
/// déclarent ; `CrashlyticsService.setUser` existait, mais rien ne l'appelait.
/// Ces contrôles passent par les vraies méthodes d'`AuthNotifier` : c'est
/// l'état d'authentification qui porte l'identifiant, quel que soit le chemin.
void main() {
  final membre = UserEntity(
    id: 'u42',
    pseudo: 'Awa',
    countryCode: 'BF',
    subscriptionPlan: SubscriptionPlan.free,
    referralCode: 'AB12CD',
    referralEarnings: 0,
    createdAt: DateTime(2026, 9, 1),
  );

  late List<String> transmis;
  late ProviderContainer container;
  late AuthNotifier auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transmis = [];
    final depot = _Depot(membre);
    container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthNotifier(
          SendOtpUseCase(depot), VerifyOtpUseCase(depot), depot)),
    ]);
    suivreCompteCrashlytics(container, definir: (id) async => transmis.add(id));
    auth = container.read(authProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('une session restaurée au démarrage transmet l\'identifiant du compte', () async {
    await auth.restoreSession();
    expect(transmis, ['u42']);
  });

  test('une connexion transmet l\'identifiant, la déconnexion l\'efface', () async {
    await auth.verifyEmailOtp(email: 'awa@example.com', otp: '123456');
    await auth.logout();
    expect(transmis, ['u42', ''],
        reason: 'après déconnexion, un plantage ne doit plus être attribué à '
                'l\'ancien compte');
  });

  test('la suppression du compte efface l\'identifiant', () async {
    await auth.restoreSession();
    await auth.deleteAccount();
    expect(transmis.last, '');
  });

  test('une session expirée efface l\'identifiant', () async {
    await auth.restoreSession();
    auth.reset();
    expect(transmis.last, '');
  });

  test('un échec en cours de session ne déconnecte pas Crashlytics', () async {
    await auth.restoreSession();
    // Refus du serveur à l'acceptation des conditions : chargement, puis
    // erreur. Le membre reste connecté, l'identifiant aussi.
    await auth.acceptTerms();
    expect(container.read(authProvider), isA<AuthError>());
    expect(transmis, ['u42']);
  });

  test('un Crashlytics indisponible n\'empêche pas la connexion', () async {
    container.dispose();
    container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) {
        final depot = _Depot(membre);
        return AuthNotifier(SendOtpUseCase(depot), VerifyOtpUseCase(depot), depot);
      }),
    ]);
    suivreCompteCrashlytics(container,
        definir: (_) async => throw StateError('Firebase absent'));

    await container.read(authProvider.notifier).restoreSession();
    expect(container.read(authProvider), isA<AuthAuthenticated>());
  });

  test('main.dart branche le suivi avant de restaurer la session', () {
    // Branché après, l'écouteur manquerait le compte restauré au démarrage —
    // le cas le plus courant : la plupart des lancements ne passent pas par
    // un écran de connexion.
    final source = File('lib/main.dart').readAsStringSync();
    final suivi = source.indexOf('suivreCompteCrashlytics(container)');
    final restauration = source.indexOf('.restoreSession()');
    expect(suivi, isNonNegative, reason: 'le suivi Crashlytics n\'est plus branché');
    expect(restauration, isNonNegative, reason: 'restoreSession introuvable');
    expect(suivi, lessThan(restauration),
        reason: 'le suivi doit précéder la restauration de session');
  });

  test('les états intermédiaires ne touchent pas à l\'identifiant', () {
    expect(identifiantCrashlytics(AuthAuthenticated(membre)), 'u42');
    expect(identifiantCrashlytics(TermsAccepted(membre)), 'u42');
    expect(identifiantCrashlytics(AuthInitial()), '');
    for (final etat in <AuthState>[
      AuthUnknown(), AuthLoading(), AuthError('x'),
      OtpSent('+22670000000'), EmailOtpSent('a@b.c', isNewUser: false),
    ]) {
      expect(identifiantCrashlytics(etat), isNull, reason: '${etat.runtimeType}');
    }
  });
}

/// Un compte valide côté serveur ; seule l'acceptation des conditions échoue.
class _Depot implements AuthRepository {
  _Depot(this.membre);
  final UserEntity membre;

  @override
  Future<bool> isLoggedIn() async => true;
  @override
  Future<Either<Failure, UserEntity>> getProfile() async => Right(membre);
  @override
  Future<UserEntity> verifyEmailOtp({required String email, required String otp}) async => membre;
  @override
  Future<Either<Failure, void>> logout() async => const Right(null);
  @override
  Future<Either<Failure, void>> deleteAccount() async => const Right(null);
  @override
  Future<Either<Failure, DateTime>> acceptTerms() async =>
      const Left(ServerFailure('refus'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
