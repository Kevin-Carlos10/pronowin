/// Le bilan de tous les paris d'une bankroll, tel que le serveur le compte.
///
/// ── Pourquoi il ne se calcule plus sur place ──────────────────────────────
///
/// L'historique renvoyé par l'API est plafonné à cinquante lignes — charger
/// mille paris sur un téléphone n'a pas de sens, et la limite n'était donc pas
/// le problème. Le problème était qu'elle ne se voyait pas : l'écran calculait
/// ses compteurs, son taux de réussite et sa courbe **depuis cette liste**, et
/// les présentait comme le bilan complet.
///
/// Au cinquante-et-unième pari, tous ces chiffres devenaient faux. Rien ne
/// changeait à l'écran : ni avertissement, ni « 50 derniers », ni période. Un
/// utilisateur assidu lisait son taux de réussite sur un échantillon tronqué
/// en croyant lire son bilan.
///
/// Ces chiffres sont maintenant comptés par la base, sur tout l'historique.
class ResumeParis {
  /// Tous les paris posés, quel que soit leur statut.
  final int total;

  final int gagnes;
  final int perdus;

  /// Remboursés (PUSH) : tranchés, mais sans départager.
  final int rembourses;

  /// Paris dont l'issue n'est pas encore connue.
  final int enAttente;

  /// Taux de réussite en pourcentage, remboursés exclus du dénominateur.
  final double tauxBrut;

  /// Résultat net réalisé, sur les paris réglés.
  ///
  /// C'est le seul des trois montants qui dit si l'on gagne ou si l'on perd.
  final double profitNet;

  /// Ce qui est engagé sur des paris non tranchés.
  ///
  /// Cette somme est **déjà déduite** du solde disponible : la mise part au
  /// moment où le pari est posé. L'écran l'ignorait et affichait
  /// `solde − budget` comme un « gain » — si bien que poser un pari se lisait
  /// comme une perte, flèche rouge comprise, alors que rien n'était perdu.
  final double misesEnCours;

  const ResumeParis({
    required this.total,
    required this.gagnes,
    required this.perdus,
    required this.rembourses,
    required this.enAttente,
    required this.tauxBrut,
    required this.profitNet,
    this.misesEnCours = 0,
  });

  factory ResumeParis.depuisApi(Map<String, dynamic> j) => ResumeParis(
        total:      (j['total']         as num?)?.toInt()    ?? 0,
        gagnes:     (j['gagnes']        as num?)?.toInt()    ?? 0,
        perdus:     (j['perdus']        as num?)?.toInt()    ?? 0,
        rembourses: (j['rembourses']    as num?)?.toInt()    ?? 0,
        enAttente:  (j['en_attente']    as num?)?.toInt()    ?? 0,
        tauxBrut:   (j['taux_reussite'] as num?)?.toDouble() ?? 0.0,
        profitNet:  (j['profit_net']    as num?)?.toDouble() ?? 0.0,
        misesEnCours:
            (j['mises_en_cours'] as num?)?.toDouble() ?? 0.0,
      );
}
