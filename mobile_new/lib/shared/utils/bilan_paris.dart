/// Lecture d'un bilan de paris : ce qui est mesuré, ce qui ne l'est pas encore.
///
/// L'API renvoie un `taux_reussite` numérique en toutes circonstances. Quand
/// aucun pari n'est encore tranché, ce taux vaut 0 — non pas parce que le
/// joueur perd, mais parce qu'il n'y a rien à diviser. Affiché tel quel, ce
/// zéro devient une affirmation fausse : « 0 % de réussite » sur un compte qui
/// vient de poser son premier pari.
///
/// Cette classe sépare les deux cas une bonne fois, pour que l'écran n'ait plus
/// à trancher lui-même.
class BilanParis {
  /// Paris posés, tous statuts confondus.
  final int suivis;

  /// Paris gagnés.
  final int gagnes;

  /// Paris perdus.
  final int perdus;

  /// Taux de réussite tel que renvoyé par l'API, en pourcentage.
  final double tauxBrut;

  /// Série de victoires en cours.
  final int serie;

  const BilanParis({
    required this.suivis,
    required this.gagnes,
    required this.perdus,
    required this.tauxBrut,
    required this.serie,
  });

  /// Construit un bilan depuis la réponse brute de `userStatsProvider`.
  factory BilanParis.depuisApi(Map<String, dynamic> stats) => BilanParis(
        suivis:   (stats['pronostics_suivis'] as num?)?.toInt()    ?? 0,
        gagnes:   (stats['paris_gagnes']      as num?)?.toInt()    ?? 0,
        perdus:   (stats['paris_perdus']      as num?)?.toInt()    ?? 0,
        tauxBrut: (stats['taux_reussite']     as num?)?.toDouble() ?? 0.0,
        serie:    (stats['serie_gagnante']    as num?)?.toInt()    ?? 0,
      );

  /// Paris dont l'issue est connue — le dénominateur du taux de réussite.
  ///
  /// Les paris remboursés (statut PUSH) ne comptent ni comme gagnés ni comme
  /// perdus : ils ne figurent donc pas ici, et ils gonflent [enAttente]. C'est
  /// volontaire — un remboursement ne dit rien de la justesse d'un pronostic.
  int get regles => gagnes + perdus;

  /// Paris posés dont l'issue n'est pas encore connue.
  int get enAttente => (suivis - regles).clamp(0, suivis);

  /// Aucun pari tranché : le taux de réussite et la série n'ont pas de valeur
  /// mesurée, seulement une valeur par défaut. Rien ne doit être chiffré.
  bool get vierge => regles == 0;

  /// Taux de réussite, ou `null` tant qu'il n'a pas de dénominateur.
  double? get taux => vierge ? null : tauxBrut;

  /// Aucun pari du tout : la carte n'a pas lieu d'être affichée.
  bool get sansAucunPari => suivis == 0;
}
