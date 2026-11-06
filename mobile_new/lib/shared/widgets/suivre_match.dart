import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/parametres/presentation/providers/settings_provider.dart';
import '../../l10n/app_strings.dart';
import '../providers/favoris_provider.dart';
import '../utils/messages.dart';

/// Suivre un match (18 octobre 2026).
///
/// Mettre un match en favori déclenche, côté serveur, le coup d'envoi, chaque
/// but et le résultat en notification. Le bouton était pourtant un marque-page
/// discret, « Ajouter aux favoris » : rien ne disait qu'il servait à ça. Un
/// seul match avait été mis en favori en trente jours, pour une soixantaine
/// d'utilisateurs actifs par semaine — les alertes de but ne touchaient
/// presque personne.
///
/// Partout désormais, une cloche, comme sur Sofascore : « Suivre ce match ».
/// Le premier appui dit ce qu'on recevra.
const IconData iconeMatchSuivi = Icons.notifications_active_rounded;
const IconData iconeMatchNonSuivi = Icons.notifications_none_rounded;

IconData iconeSuivi(bool suivi) => suivi ? iconeMatchSuivi : iconeMatchNonSuivi;

/// Le libellé du bouton, pour les lecteurs d'écran et l'infobulle.
String libelleSuivi(BuildContext context, bool suivi) =>
    suivi ? tr(context, "Ne plus suivre ce match") : tr(context, "Suivre ce match");

/// Bascule le suivi de [matchId] et dit ce que cela change.
///
/// Le message attend la réponse du serveur : si elle échoue, le suivi revient
/// à son état d'avant, et rien n'est annoncé. [termine] : un match fini
/// n'enverra plus d'alerte, il rejoint seulement la liste des matchs suivis.
Future<void> basculerSuivi(BuildContext context, String matchId,
    {bool termine = false}) async {
  // Tout ce qui dépend de l'écran est lu avant l'attente : il peut avoir
  // disparu à la réponse du serveur.
  final messager = ScaffoldMessenger.maybeOf(context);
  final routeur = GoRouter.maybeOf(context);
  final plusSuivi = tr(context, "Tu ne suis plus ce match.");
  final ajouteFini = tr(context, "Match ajouté à tes matchs suivis.");
  final alertesCoupees = tr(context, "Match suivi, mais les alertes de match sont coupées dans les Paramètres.");
  final activer = tr(context, "Activer");
  final suiviOk = tr(context, "Match suivi : tu recevras le coup d'envoi, les buts et le résultat.");
  // Le conteneur, pas `ref` : `ref` ne sert plus une fois l'écran fermé.
  final conteneur = ProviderScope.containerOf(context, listen: false);
  bool suivi() => conteneur.read(favorisProvider).valueOrNull?.matchIds.contains(matchId) ?? false;

  final avant = suivi();
  await conteneur.read(favorisProvider.notifier).basculerMatch(matchId);
  final apres = suivi();
  if (apres == avant) return;

  if (!apres) {
    afficherMessageVia(messager, plusSuivi, duree: const Duration(seconds: 2));
  } else if (termine) {
    afficherMessageVia(messager, ajouteFini, type: TypeMessage.succes);
  } else if (!conteneur.read(settingsProvider).notifMatch) {
    // Les alertes de match sont coupées dans les Paramètres : le suivi ne
    // donnerait rien, il faut le dire.
    afficherMessageVia(messager, alertesCoupees,
      type: TypeMessage.alerte,
      duree: const Duration(seconds: 6),
      action: routeur == null ? null
          : SnackBarAction(label: activer, onPressed: () => routeur.push('/parametres')));
  } else {
    afficherMessageVia(messager, suiviOk, type: TypeMessage.succes);
  }
}
