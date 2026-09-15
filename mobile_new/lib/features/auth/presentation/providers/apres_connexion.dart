import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../compte/presentation/providers/compte_provider.dart';
import '../../../notifications/presentation/providers/fcm_service.dart';
import 'auth_provider.dart';

/// Ce qu'il faut faire dès qu'une session s'ouvre, quel que soit le chemin.
///
/// Ces gestes n'existaient que sur l'écran de saisie du code e-mail. La
/// connexion Google, qui ne passe pas par cet écran, n'en faisait aucun — et
/// aucune erreur ne le signalait :
///
///  * l'écran de connexion restait ouvert sur un utilisateur pourtant
///    authentifié, qui devait le refermer à la main ;
///  * les fournisseurs gardaient les données de l'état invité : bankroll vide,
///    profil absent, statistiques à zéro, jusqu'au prochain redémarrage ;
///  * le jeton FCM obtenu avant la connexion restait orphelin, donc **aucune
///    notification** n'arrivait sur ce compte.
///
/// Regrouper la séquence ici évite qu'un futur fournisseur — Apple, demain —
/// hérite du même oubli.
void apresConnexionReussie(WidgetRef ref) {
  ref.invalidate(isLoggedInProvider);
  ref.invalidate(bankrollProvider);
  ref.invalidate(bankrollStatsProvider);
  ref.invalidate(profileProvider);
  ref.invalidate(userStatsProvider);

  // Rattache au compte le jeton obtenu en mode invité. Sans attente : une
  // notification qui tarde ne doit pas retenir l'utilisateur sur un écran de
  // connexion qu'il a terminé.
  FCMService.registerCurrentToken(ref);
}
