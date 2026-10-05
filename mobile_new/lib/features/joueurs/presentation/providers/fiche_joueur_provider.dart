import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';

/// Les statistiques d'un joueur dans une compétition, sur une saison.
class StatsCompetition {
  final String team, league;
  final String? teamLogo, leagueLogo, position;
  final int appearances, lineups, minutes, goals, assists, yellowCards, redCards,
      shots, shotsOn, keyPasses, dribblesSuccess, duelsWon, penaltiesScored, conceded, saves;
  final double? rating;
  final int? passAccuracy;

  const StatsCompetition({
    required this.team, required this.league, this.teamLogo, this.leagueLogo, this.position,
    this.appearances = 0, this.lineups = 0, this.minutes = 0, this.goals = 0, this.assists = 0,
    this.yellowCards = 0, this.redCards = 0, this.shots = 0, this.shotsOn = 0, this.keyPasses = 0,
    this.dribblesSuccess = 0, this.duelsWon = 0, this.penaltiesScored = 0, this.conceded = 0,
    this.saves = 0, this.rating, this.passAccuracy,
  });

  bool get estGardien => position == 'Goalkeeper';

  static int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  factory StatsCompetition.fromJson(Map<String, dynamic> j) => StatsCompetition(
    team: j['team'] as String? ?? '', league: j['league'] as String? ?? '',
    teamLogo: j['teamLogo'] as String?, leagueLogo: j['leagueLogo'] as String?,
    position: j['position'] as String?,
    appearances: _n(j['appearances']), lineups: _n(j['lineups']), minutes: _n(j['minutes']),
    goals: _n(j['goals']), assists: _n(j['assists']),
    yellowCards: _n(j['yellowCards']), redCards: _n(j['redCards']),
    shots: _n(j['shots']), shotsOn: _n(j['shotsOn']), keyPasses: _n(j['keyPasses']),
    dribblesSuccess: _n(j['dribblesSuccess']), duelsWon: _n(j['duelsWon']),
    penaltiesScored: _n(j['penaltiesScored']), conceded: _n(j['conceded']), saves: _n(j['saves']),
    rating: (j['rating'] as num?)?.toDouble(),
    passAccuracy: (j['passAccuracy'] as num?)?.toInt(),
  );
}

class AbsenceJoueur {
  final String motif;
  final bool suspension;
  final DateTime? debut, fin;
  const AbsenceJoueur({required this.motif, this.suspension = false, this.debut, this.fin});

  factory AbsenceJoueur.fromJson(Map<String, dynamic> j) => AbsenceJoueur(
    motif: j['motif'] as String? ?? '',
    suspension: j['suspension'] == true,
    debut: DateTime.tryParse(j['debut'] as String? ?? ''),
    fin: DateTime.tryParse(j['fin'] as String? ?? ''),
  );
}

class TransfertJoueur {
  final DateTime? date;
  final String type, depuis, vers;
  final String? depuisLogo, versLogo;
  const TransfertJoueur({this.date, required this.type, required this.depuis, required this.vers,
      this.depuisLogo, this.versLogo});

  factory TransfertJoueur.fromJson(Map<String, dynamic> j) => TransfertJoueur(
    date: DateTime.tryParse(j['date'] as String? ?? ''),
    type: j['type'] as String? ?? '',
    depuis: j['depuis'] as String? ?? '', vers: j['vers'] as String? ?? '',
    depuisLogo: j['depuisLogo'] as String?, versLogo: j['versLogo'] as String?,
  );
}

/// La fiche d'un joueur, telle que `/pronostics/joueurs/:id` la publie.
class FicheJoueur {
  final int id;
  final String name;
  final String? photo, nationality, height, weight, birthPlace;
  final int? age;
  final DateTime? birthDate;
  final bool injured;
  final int season;
  final List<StatsCompetition> stats;
  final List<AbsenceJoueur> absences;
  final List<TransfertJoueur> transferts;

  const FicheJoueur({
    required this.id, required this.name, required this.season,
    this.photo, this.nationality, this.height, this.weight, this.birthPlace, this.age,
    this.birthDate, this.injured = false,
    this.stats = const [], this.absences = const [], this.transferts = const [],
  });

  /// Le poste et le club : ceux de la compétition la plus jouée.
  StatsCompetition? get principale => stats.isEmpty ? null : stats.first;

  factory FicheJoueur.fromJson(Map<String, dynamic> j) => FicheJoueur(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    photo: j['photo'] as String?,
    nationality: j['nationality'] as String?,
    height: j['height'] as String?, weight: j['weight'] as String?,
    birthPlace: j['birthPlace'] as String?,
    age: (j['age'] as num?)?.toInt(),
    birthDate: DateTime.tryParse(j['birthDate'] as String? ?? ''),
    injured: j['injured'] == true,
    season: (j['season'] as num?)?.toInt() ?? DateTime.now().year,
    stats: [for (final s in (j['stats'] as List? ?? const [])) StatsCompetition.fromJson(s as Map<String, dynamic>)],
    absences: [for (final a in (j['absences'] as List? ?? const [])) AbsenceJoueur.fromJson(a as Map<String, dynamic>)],
    transferts: [for (final t in (j['transferts'] as List? ?? const [])) TransfertJoueur.fromJson(t as Map<String, dynamic>)],
  );
}

/// Ce qu'on sait déjà du joueur en ouvrant sa fiche (nom et photo de la
/// ligne touchée) : l'en-tête s'affiche avant la réponse du serveur.
typedef ApercuJoueur = ({String nom, String? photo});

/// Le joueur n'existe pas chez le fournisseur : rien à réessayer.
class JoueurIntrouvable implements Exception {
  const JoueurIntrouvable();
}

final ficheJoueurProvider = FutureProvider.autoDispose.family<FicheJoueur, int>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/joueurs/$id');
    return FicheJoueur.fromJson(r.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) throw const JoueurIntrouvable();
    rethrow;
  }
});
