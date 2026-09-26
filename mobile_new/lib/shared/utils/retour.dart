import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Revenir en arrière, ou aller quelque part quand il n'y a pas d'arrière.
///
/// ── Pourquoi cette fonction existe ────────────────────────────────────────
///
/// Les notifications transportent un lien profond — `/pronostics/{id}` pour un
/// match, `/compte` pour le parrainage, `/pronostics` pour un message système.
/// Quand l'utilisateur tape la notification, `fcm_service` fait :
///
///     context.go(deepLink);
///
/// `go()` **remplace** la pile de navigation. L'écran d'arrivée devient
/// l'unique route : il n'y a plus rien derrière lui. La flèche retour appelait
/// alors `context.pop()`, `canPop()` valait `false`, et go_router levait
/// `GoError: There is nothing to pop`.
///
/// Crashlytics l'a mesuré sur la version 1.0.0 : 41 plantages pour 4
/// utilisateurs. Ce n'est pas un cas limite — c'est le geste de quiconque tape
/// une notification puis revient en arrière, sur l'application dont les
/// notifications sont le cœur.
///
/// ── Ce qu'elle change, et ce qu'elle ne change pas ────────────────────────
///
/// Quand `canPop()` est vrai — la quasi-totalité des cas — le comportement est
/// **exactement** celui d'avant : `pop()`. La différence n'existe que là où
/// l'application plantait. Cette fonction ne peut donc pas casser un chemin qui
/// fonctionne ; elle ne fait que remplacer une exception par une destination.
///
/// ── Le repli ──────────────────────────────────────────────────────────────
///
/// `repli` est l'endroit où aller quand il n'y a rien à dépiler. Il doit être
/// l'écran dont la page consultée dépend : depuis une fiche de match,
/// `/pronostics` ; depuis le parrainage, `/compte`. Renvoyer partout vers
/// `/home` fonctionnerait, mais donnerait à l'utilisateur l'impression d'avoir
/// été éjecté plutôt que d'être remonté d'un cran.
///
/// Le motif correct existait déjà dans `completer_profil_page.dart`, écrit une
/// fois et oublié dans les vingt autres endroits.
void retourOuAller(BuildContext context, {String repli = '/home'}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(repli);
  }
}
