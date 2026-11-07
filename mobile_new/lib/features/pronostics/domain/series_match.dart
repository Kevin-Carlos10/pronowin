/// Les « Séries » d'un match (7 novembre 2026) : ce que Sofascore affiche sous
/// ce nom — « Victoires 3 », « Aucune défaite 4 », « Plus de 2,5 buts 7/9 » —,
/// pour chaque équipe et pour leurs face-à-face.
///
/// Le serveur compte sur les dix derniers matchs terminés de chaque équipe
/// (`forme_recente.service.ts`) ; ce fichier choisit ce qui mérite d'être lu.
/// Une série ordinaire (une victoire, 5 matchs sur 10 à plus de 2,5 buts) ne
/// dit rien et n'est pas affichée.
library;

/// Les comptes du serveur pour une équipe.
class SeriesEquipe {
  final int sur, victoires, sansDefaite, sansVictoire, defaites, marque, sansEncaisser;
  final int plusDe25Buts, lesDeuxMarquent, cleanSheets, nAPasMarque;
  const SeriesEquipe({
    required this.sur, this.victoires = 0, this.sansDefaite = 0, this.sansVictoire = 0,
    this.defaites = 0, this.marque = 0, this.sansEncaisser = 0, this.plusDe25Buts = 0,
    this.lesDeuxMarquent = 0, this.cleanSheets = 0, this.nAPasMarque = 0,
  });

  static SeriesEquipe? fromJson(Object? j) {
    if (j is! Map) return null;
    int n(String c) => (j[c] as num?)?.toInt() ?? 0;
    return SeriesEquipe(
      sur: n('sur'), victoires: n('victoires'), sansDefaite: n('sansDefaite'),
      sansVictoire: n('sansVictoire'), defaites: n('defaites'), marque: n('marque'),
      sansEncaisser: n('sansEncaisser'), plusDe25Buts: n('plusDe25Buts'),
      lesDeuxMarquent: n('lesDeuxMarquent'), cleanSheets: n('cleanSheets'),
      nAPasMarque: n('nAPasMarque'),
    );
  }
}

/// Une ligne de la carte : le libellé (clé de traduction) et sa valeur
/// (« 4 » pour une série en cours, « 7/10 » pour un compte).
class FaitSerie {
  final String libelle, valeur;
  const FaitSerie(this.libelle, this.valeur);

  @override
  bool operator ==(Object other) => other is FaitSerie && other.libelle == libelle && other.valeur == valeur;
  @override
  int get hashCode => Object.hash(libelle, valeur);
  @override
  String toString() => '$libelle $valeur';
}

/// Les faits qui méritent d'être lus pour une équipe.
List<FaitSerie> faitsNotables(SeriesEquipe s) {
  if (s.sur == 0) return const [];
  final faits = <FaitSerie>[];
  // Une seule série de résultats : la plus parlante.
  if (s.victoires >= 2) {
    faits.add(FaitSerie('Victoires de suite', '${s.victoires}'));
  } else if (s.sansDefaite >= 3) {
    faits.add(FaitSerie('Sans défaite', '${s.sansDefaite}'));
  }
  if (s.defaites >= 2) {
    faits.add(FaitSerie('Défaites de suite', '${s.defaites}'));
  } else if (s.sansVictoire >= 3) {
    faits.add(FaitSerie('Sans victoire', '${s.sansVictoire}'));
  }
  if (s.sansEncaisser >= 2) faits.add(FaitSerie('Sans encaisser', '${s.sansEncaisser}'));
  if (s.marque >= 4) faits.add(FaitSerie('A marqué à chaque match', '${s.marque}'));
  // Les comptes ne disent quelque chose que sur cinq matchs au moins.
  if (s.sur >= 5) {
    String sur(int k) => '$k/${s.sur}';
    if (s.plusDe25Buts >= (s.sur * 0.6).ceil()) {
      faits.add(FaitSerie('Plus de 2,5 buts', sur(s.plusDe25Buts)));
    } else if (s.sur - s.plusDe25Buts >= (s.sur * 0.7).ceil()) {
      faits.add(FaitSerie('Moins de 2,5 buts', sur(s.sur - s.plusDe25Buts)));
    }
    if (s.lesDeuxMarquent >= (s.sur * 0.6).ceil()) {
      faits.add(FaitSerie('Les deux équipes marquent', sur(s.lesDeuxMarquent)));
    }
    if (s.cleanSheets >= (s.sur * 0.5).ceil()) {
      faits.add(FaitSerie('Matchs sans encaisser', sur(s.cleanSheets)));
    }
    if (s.nAPasMarque >= (s.sur * 0.4).ceil()) {
      faits.add(FaitSerie("Matchs sans marquer", sur(s.nAPasMarque)));
    }
  }
  return faits;
}

/// Un face-à-face passé, réduit à ce qu'il faut pour les séries.
typedef Confrontation = ({String domicile, String exterieur, int butsDom, int butsExt});

/// Les séries des face-à-face, du plus récent au plus ancien. [equipeA] et
/// [equipeB] : les équipes du match, sous les noms des confrontations.
List<FaitSerie> faitsFaceAFace(List<Confrontation> matchs, {required String equipeA, required String equipeB}) {
  final n = matchs.length;
  if (n < 3) return const [];
  final faits = <FaitSerie>[];
  final plus25 = matchs.where((m) => m.butsDom + m.butsExt >= 3).length;
  final deux = matchs.where((m) => m.butsDom > 0 && m.butsExt > 0).length;
  if (plus25 >= (n * 0.6).ceil()) {
    faits.add(FaitSerie('Plus de 2,5 buts', '$plus25/$n'));
  } else if (n - plus25 >= (n * 0.7).ceil()) {
    faits.add(FaitSerie('Moins de 2,5 buts', '${n - plus25}/$n'));
  }
  if (deux >= (n * 0.6).ceil()) faits.add(FaitSerie('Les deux équipes marquent', '$deux/$n'));
  return faits;
}

/// Série en cours d'une équipe sans défaite face à l'autre ; 0 si la
/// confrontation la plus récente ne la concerne pas ou qu'elle l'a perdue.
int sansDefaiteFaceA(List<Confrontation> matchs, String equipe) {
  var serie = 0;
  for (final m in matchs) {
    final dom = m.domicile == equipe, ext = m.exterieur == equipe;
    if (!dom && !ext) break;
    final perdu = dom ? m.butsDom < m.butsExt : m.butsExt < m.butsDom;
    if (perdu) break;
    serie++;
  }
  return serie;
}
