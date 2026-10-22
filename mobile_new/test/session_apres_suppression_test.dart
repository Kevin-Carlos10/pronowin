import 'dart:async';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/network/failures.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/auth/domain/repositories/auth_repository.dart';
import 'package:pronowin/features/auth/presentation/providers/auth_provider.dart';

/// Après « Supprimer le compte », la connexion suivante ne passe pas pour une
/// session déjà ouverte.
///
/// Vidéo du 2 octobre 2026 : compte supprimé, puis « Se connecter avec
/// Apple » — l'app reste sur un écran gris. Pendant la connexion
/// (`AuthLoading`), le statut affiché retombait sur une lecture du jeton
/// gardée en cache, que la suppression ne relisait pas : « connecté ». Le
/// routeur renvoyait vers l'accueil au milieu de la connexion.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pendant la connexion qui suit une suppression, la session reste fermée', () async {
    final depot = _Depot();
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(depot),
      // Le cache périmé : lu quand le compte existait encore.
      isLoggedInProvider.overrideWith((ref) async => true),
    ]);
    addTearDown(c.dispose);
    await c.read(isLoggedInProvider.future);
    final auth = c.read(authProvider.notifier);

    await auth.verifyEmailOtp(email: 'a@exemple.test', otp: '000000');
    expect(c.read(effectiveLoggedInProvider), isTrue);

    await auth.deleteAccount();
    expect(c.read(effectiveLoggedInProvider), isFalse);

    // La connexion suivante, en cours : le serveur n'a pas encore répondu.
    final envoi = auth.sendEmailOtp('b@exemple.test');
    expect(c.read(authProvider), isA<AuthLoading>());
    expect(c.read(effectiveLoggedInProvider), isFalse,
        reason: "sinon le routeur quitte l'écran de connexion pour l'accueil");

    depot.reponseOtp.complete(true);
    await envoi;
    expect(c.read(effectiveLoggedInProvider), isFalse);
  });

  test("au démarrage à froid, seul le jeton en stockage peut trancher", () async {
    // Contrepartie : avant toute restauration, aucun verdict n'existe encore.
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Depot()),
      isLoggedInProvider.overrideWith((ref) async => true),
    ]);
    addTearDown(c.dispose);
    await c.read(isLoggedInProvider.future);

    expect(c.read(authProvider), isA<AuthUnknown>());
    expect(c.read(effectiveLoggedInProvider), isTrue);
  });

  test('une connexion en cours sur une session ouverte la garde ouverte', () async {
    // Ex. l'acceptation des conditions, qui passe par AuthLoading : les pages
    // réservées aux comptes ne doivent pas renvoyer vers la connexion.
    final depot = _Depot();
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(depot),
      isLoggedInProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(c.dispose);
    await c.read(isLoggedInProvider.future);
    final auth = c.read(authProvider.notifier);

    await auth.verifyEmailOtp(email: 'a@exemple.test', otp: '000000');
    final acceptation = auth.acceptTerms();
    expect(c.read(authProvider), isA<AuthLoading>());
    expect(c.read(effectiveLoggedInProvider), isTrue);

    depot.reponseConditions.complete(Right(DateTime(2026, 10, 2)));
    await acceptation;
  });

  test("après une connexion, l'abonnement et le parrainage sont relus aussi", () {
    // Vidéo du 3 octobre 2026 : déconnexion, reconnexion, et l'onglet
    // Abonnement affichait « Actif sans limite » sans « Gérer mon
    // abonnement » — il gardait ce qu'il avait lu en invité.
    final source = File('lib/features/auth/presentation/providers/apres_connexion.dart').readAsStringSync();
    expect(source, contains('rafraichirDonneesCompte(ref)'));
  });
}

final _utilisateur = UserEntity(
  id: 'u1', pseudo: 'Parieur_TEST', countryCode: 'BF',
  subscriptionPlan: SubscriptionPlan.free, referralCode: 'ABC123',
  referralEarnings: 0, createdAt: DateTime(2026, 10, 2),
);

class _Depot implements AuthRepository {
  final reponseOtp = Completer<bool>();
  final reponseConditions = Completer<Either<Failure, DateTime>>();

  @override
  Future<UserEntity> verifyEmailOtp({required String email, required String otp}) async => _utilisateur;

  @override
  Future<Either<Failure, void>> deleteAccount() async => const Right(null);

  @override
  Future<bool> sendEmailOtp(String email) => reponseOtp.future;

  @override
  Future<Either<Failure, DateTime>> acceptTerms() => reponseConditions.future;

  @override
  Future<bool> isLoggedIn() async => false;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
