import '../../domain/entities/league_entity.dart';

class LeagueModel extends LeagueEntity {
  const LeagueModel({
    required super.id, required super.name, required super.country,
    super.logo, required super.matchCount,
  });

  factory LeagueModel.fromJson(Map<String, dynamic> j) => LeagueModel(
    id:         j['id'] as String,
    name:       j['name'] as String,
    country:    j['country'] as String? ?? '',
    logo:       j['logo'] as String?,
    matchCount: j['match_count'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    'country':     country,
    'logo':        logo,
    'match_count': matchCount,
  };
}
