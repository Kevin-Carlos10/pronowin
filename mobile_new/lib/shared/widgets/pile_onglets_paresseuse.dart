import 'package:flutter/material.dart';

/// Une pile d'onglets qui ne construit que ceux qu'on a ouverts.
///
/// ── Ce que coûtait `IndexedStack` ─────────────────────────────────────────
///
/// `IndexedStack` n'en peint qu'un, mais il les **construit tous**. Or chaque
/// onglet de PronoWin observe des providers qui appellent le réseau dès leur
/// première lecture. Ouvrir l'application sur l'accueil déclenchait donc aussi
/// la bankroll, les tutoriels, le parrainage et les quatre variantes de la
/// liste des pronostics.
///
/// Relevé dans les journaux nginx, un démarrage à froid réel :
///
///     13:32:40  /pronostics?date_filter=week&limit=50
///     13:32:41  /auth/profile
///     13:32:42  /auth/profile
///     13:32:42  /notifications/my
///     13:32:43  /actualites  /bankroll  /config  /favorites  /favorites
///     13:32:43  /pronostics/counts-by-day  /pronostics/day-summary
///     13:32:43  /pronostics/performance  /pronostics/stats
///     13:32:43  /pronostics?date_filter=2026-09-21  ?date_filter=today
///     13:32:43  ?date_filter=yesterday
///     13:32:43  /referral  /subscriptions/current  /tutorials
///
/// Vingt requêtes en trois secondes pour afficher un seul écran. L'utilisateur
/// paie le chargement des cinq onglets, en données comme en attente, avant même
/// de savoir s'il en ouvrira un deuxième.
///
/// ── Ce que celle-ci change, et ce qu'elle garde ───────────────────────────
///
/// Un onglet jamais ouvert reste un espace vide : aucun provider lu, aucune
/// requête. Dès qu'on l'ouvre il est construit, et il **reste** dans la pile —
/// c'est ce que `IndexedStack` apportait et qu'il fallait conserver. Revenir
/// sur un onglet déjà vu ne recharge rien, ne reperd ni le défilement ni les
/// filtres.
///
/// Autrement dit : on ne diffère que la première construction. Le reste du
/// comportement est celui d'avant.
class PileOngletsParesseuse extends StatefulWidget {
  /// L'onglet affiché.
  final int index;

  /// Les onglets, dans l'ordre de la barre de navigation.
  final List<Widget> children;

  const PileOngletsParesseuse({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<PileOngletsParesseuse> createState() => _PileOngletsParesseuseState();
}

class _PileOngletsParesseuseState extends State<PileOngletsParesseuse> {
  /// Les onglets déjà ouverts au moins une fois. On n'en retire jamais rien :
  /// c'est précisément ce qui préserve leur état.
  final Set<int> _ouverts = <int>{};

  @override
  void initState() {
    super.initState();
    _ouverts.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant PileOngletsParesseuse ancien) {
    super.didUpdateWidget(ancien);
    // Appelé avant `build` dans la même frame : noter l'onglet ici suffit,
    // sans `setState` qui provoquerait une seconde construction inutile.
    _ouverts.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: <Widget>[
        for (var i = 0; i < widget.children.length; i++)
          if (_ouverts.contains(i))
            OngletVisible(visible: i == widget.index, child: widget.children[i])
          else
            // Un substitut sans dimension propre : il ne doit pas peser dans
            // le calcul de taille de la pile, sinon un onglet jamais ouvert
            // déciderait de la hauteur de celui qu'on regarde.
            const SizedBox.shrink(),
      ],
    );
  }
}

/// Dit à un onglet s'il est celui qu'on regarde.
///
/// Un onglet construit reste vivant quand on passe au suivant — c'est voulu,
/// c'est ce qui préserve son état. Mais ses minuteurs continuent eux aussi, et
/// un rafraîchissement toutes les 45 secondes derrière un écran que personne ne
/// regarde coûte des données et de la batterie sans rien apporter.
///
/// La pile porte déjà l'information : elle sait quel onglet elle affiche. La
/// faire redescendre ici évite d'en tenir une seconde copie ailleurs, qui
/// finirait par diverger de celle-ci.
///
/// Hors d'une pile — page ouverte seule, banc d'essai — la réponse est `true` :
/// une page qu'on affiche directement est par définition visible.
class OngletVisible extends InheritedWidget {
  final bool visible;

  const OngletVisible({
    super.key,
    required this.visible,
    required super.child,
  });

  static bool de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OngletVisible>()?.visible ?? true;

  @override
  bool updateShouldNotify(OngletVisible ancien) => ancien.visible != visible;
}
