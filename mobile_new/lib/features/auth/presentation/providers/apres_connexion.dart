import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../compte/presentation/pages/compte_page.dart' show rafraichirDonneesCompte;
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
  // La même liste que le geste de rafraîchissement et la déconnexion. Celle-ci
  // avait la sienne, écrite à la main, sans l'abonnement ni le parrainage :
  // après une reconnexion, l'onglet Abonnement gardait ce qu'il avait lu en
  // invité — « Actif sans limite », sans « Gérer mon abonnement » (vidéo du
  // 3 octobre 2026).
  rafraichirDonneesCompte(ref);

  // Rattache au compte le jeton obtenu en mode invité. Sans attente : une
  // notification qui tarde ne doit pas retenir l'utilisateur sur un écran de
  // connexion qu'il a terminé.
  FCMService.registerCurrentToken(ref);
}
