import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/crashlytics_service.dart';
import 'auth_provider.dart';

/// Rattache les rapports de plantage au compte connecté.
///
/// La politique de confidentialité, le site et la fiche App Store déclarent
/// que les rapports de plantage sont associés à l'identifiant du compte.
/// `CrashlyticsService.setUser` existait pour cela depuis le premier jour,
/// mais rien ne l'appelait : la déclaration décrivait une collecte qui n'avait
/// pas lieu, et un plantage signalé par un membre restait introuvable parmi
/// les autres.
///
/// Un seul écouteur sur [authProvider], plutôt qu'un appel par écran : la
/// connexion se fait par e-mail, Google, Apple ou par restauration de session
/// au démarrage, et se termine par déconnexion, suppression du compte ou
/// session expirée. Chacun de ces chemins passe par l'état d'authentification,
/// aucun n'a besoin de s'en souvenir — c'est l'oubli que `apres_connexion.dart`
/// avait déjà dû réparer pour la connexion Google.
///
/// À brancher sur le conteneur avant la restauration de session, pour que
/// celle-ci soit vue.
void suivreCompteCrashlytics(
  ProviderContainer container, {
  Future<void> Function(String identifiant) definir = CrashlyticsService.setUser,
}) {
  container.listen<AuthState>(authProvider, (_, etat) async {
    final identifiant = identifiantCrashlytics(etat);
    if (identifiant == null) return;
    try {
      await definir(identifiant);
    } catch (e) {
      // Crashlytics absent (web) ou indisponible : un identifiant non
      // transmis ne doit jamais interrompre une connexion.
      debugPrint('[Crashlytics] identifiant non transmis : $e');
    }
  });
}

/// L'identifiant à donner à Crashlytics pour [etat] : celui du compte
/// connecté, `''` pour l'effacer au retour à l'état invité, `null` pour ne
/// rien changer.
///
/// Les états intermédiaires — chargement, code envoyé, erreur — ne touchent
/// pas à l'identifiant : un refus d'accepter les conditions ou un code erroné
/// ne déconnectent personne.
@visibleForTesting
String? identifiantCrashlytics(AuthState etat) => switch (etat) {
  AuthAuthenticated(:final user) => user.id,
  TermsAccepted(:final user)     => user.id,
  AuthInitial()                  => '',
  _                              => null,
};
