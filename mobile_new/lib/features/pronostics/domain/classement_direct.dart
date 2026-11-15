import '../presentation/providers/pronostics_provider.dart' show StandingRow;
import 'entities/match_entity.dart';

/// Une ligne du classement en direct (15 novembre 2026).
class LigneDirect {
  /// La ligne recalculée : matchs joués, bilan, différence de buts, points et
  /// rang provisoires. La zone est celle de la **place**, pas de l'équipe.
  final StandingRow row;

  /// Le rang au classement officiel, avant les matchs en cours.
  final int rangAvant;

  /// Le score du moment, vu de cette équipe, si elle joue.
  final ({int pour, int contre})? enJeu;

  const LigneDirect({required this.row, required this.rangAvant, this.enJeu});

  /// Places gagnées (positif) ou perdues (négatif) depuis le classement officiel.
  int get mouvement => rangAvant - row.rank;
}

final _idDansLogo = RegExp(r'/teams/(\d+)\.(?:png|svg)');

int? _idEquipe(String? logo) {
  final m = _idDansLogo.firstMatch(logo ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

String _norme(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Le classement d'un groupe tel qu'il serait si les matchs en cours
/// s'arrêtaient sur leur score du moment — le « classement en direct » de
/// Sofascore. Calculé sur le téléphone, à partir des scores que l'application
/// reçoit déjà : aucun appel de plus au fournisseur.
///
/// `null` si aucun match en cours n'oppose deux équipes de ce groupe : le
/// classement officiel suffit. Une équipe se reconnaît à l'identifiant de son
/// logo, à défaut à son nom. Départage : points, différence de buts, puis
/// l'ordre du classement officiel — le seul repère pour le reste (buts
/// marqués, confrontations), que le fournisseur ne détaille pas ici.
List<LigneDirect>? classementEnDirect(List<StandingRow> groupe, List<MatchEntity> matchs) {
  if (groupe.isEmpty) return null;
  final officiel = [...groupe]..sort((a, b) => a.rank.compareTo(b.rank));

  int? indexDe(String nom, String? logo) {
    final id = _idEquipe(logo);
    if (id != null) {
      final i = officiel.indexWhere((r) => r.teamId == id || _idEquipe(r.teamLogo) == id);
      if (i >= 0) return i;
    }
    final n = _norme(nom);
    if (n.isEmpty) return null;
    final i = officiel.indexWhere((r) => _norme(r.teamName) == n);
    return i >= 0 ? i : null;
  }

  final enJeu = <int, ({int pour, int contre})>{};
  for (final m in matchs) {
    if (m.status != MatchStatus.live || m.homeScore == null || m.awayScore == null) continue;
    final dom = indexDe(m.homeTeam, m.homeTeamLogo);
    final ext = indexDe(m.awayTeam, m.awayTeamLogo);
    // Les deux équipes, dans ce groupe : un match d'une autre poule, ou de
    // coupe, ne touche pas ce classement.
    if (dom == null || ext == null || dom == ext) continue;
    enJeu[dom] = (pour: m.homeScore!, contre: m.awayScore!);
    enJeu[ext] = (pour: m.awayScore!, contre: m.homeScore!);
  }
  if (enJeu.isEmpty) return null;

  final provisoire = [
    for (var i = 0; i < officiel.length; i++)
      (i: i, row: officiel[i], score: enJeu[i]),
  ];
  int points(({int i, StandingRow row, ({int pour, int contre})? score}) e) {
    final s = e.score;
    return e.row.points + (s == null ? 0 : s.pour > s.contre ? 3 : s.pour == s.contre ? 1 : 0);
  }
  int ecart(({int i, StandingRow row, ({int pour, int contre})? score}) e) =>
      e.row.goalsDiff + (e.score == null ? 0 : e.score!.pour - e.score!.contre);

  provisoire.sort((a, b) {
    final p = points(b).compareTo(points(a));
    if (p != 0) return p;
    final d = ecart(b).compareTo(ecart(a));
    return d != 0 ? d : a.i.compareTo(b.i);
  });

  return [
    for (var place = 0; place < provisoire.length; place++)
      () {
        final e = provisoire[place];
        final r = e.row, s = e.score;
        final gagne = s != null && s.pour > s.contre, nul = s != null && s.pour == s.contre;
        final perd = s != null && s.pour < s.contre;
        // La zone reste attachée à la place : la 4ᵉ qualifie, quelle que
        // soit l'équipe qui l'occupe.
        final zone = officiel[place];
        return LigneDirect(
          rangAvant: r.rank,
          enJeu: s,
          row: StandingRow(
            groupId: r.groupId, groupName: r.groupName, season: r.season, teamId: r.teamId,
            isMatchTeam: r.isMatchTeam, stale: r.stale, updatedAt: r.updatedAt,
            rank: place + 1, teamName: r.teamName, teamLogo: r.teamLogo,
            played: r.played + (s == null ? 0 : 1),
            win: r.win + (gagne ? 1 : 0), draw: r.draw + (nul ? 1 : 0), lose: r.lose + (perd ? 1 : 0),
            goalsDiff: ecart(e), points: points(e), form: r.form,
            zone: zone.zone, zoneNature: zone.zoneNature, home: r.home, away: r.away,
          ),
        );
      }(),
  ];
}
