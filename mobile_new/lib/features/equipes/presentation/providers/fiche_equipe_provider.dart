import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';

/// L'identifiant d'une équipe chez le fournisseur, lu dans l'adresse de son
/// logo (`…/football/teams/85.png`).
///
/// Les matchs ne stockent pas cet identifiant ; le logo, si, et le
/// fournisseur y écrit l'identifiant. Rien d'autre à demander au serveur.
int? idEquipeDepuisLogo(String? url) {
  final m = RegExp(r'/teams/(\d+)\.(?:png|svg|webp)').firstMatch(url ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

class JoueurEffectif {
  final int? id, age, number;
  final String name;
  final String? position, photo;
  const JoueurEffectif({this.id, required this.name, this.age, this.number, this.position, this.photo});

  factory JoueurEffectif.fromJson(Map<String, dynamic> j) => JoueurEffectif(
    id: (j['id'] as num?)?.toInt(), name: j['name'] as String? ?? '',
    age: (j['age'] as num?)?.toInt(), number: (j['number'] as num?)?.toInt(),
    position: j['position'] as String?, photo: j['photo'] as String?,
  );
}

class BilanSaison {
  final String? forme, systeme;
  final int joues, victoires, nuls, defaites, cleanSheets, sansMarquer;
  final String butsPour, butsContre;
  const BilanSaison({this.forme, this.systeme, this.joues = 0, this.victoires = 0, this.nuls = 0,
      this.defaites = 0, this.cleanSheets = 0, this.sansMarquer = 0, this.butsPour = '0', this.butsContre = '0'});

  factory BilanSaison.fromJson(Map<String, dynamic> j) {
    final b = j['bilan'] as Map<String, dynamic>? ?? const {};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return BilanSaison(
      forme: j['form'] as String?,
      systeme: j['systeme'] as String?,
      joues: n(b['joues']), victoires: n(b['victoires']), nuls: n(b['nuls']), defaites: n(b['defaites']),
      cleanSheets: n(j['cleanSheetTotal']), sansMarquer: n(j['failedToScoreTotal']),
      butsPour: (j['goalsForAverage'] as Map?)?['total']?.toString() ?? '0',
      butsContre: (j['goalsAgainstAverage'] as Map?)?['total']?.toString() ?? '0',
    );
  }
}

class FicheEquipe {
  final bool partial;
  final int id;
  final String name;
  final String? country, logo;
  final int? founded;
  final ({String? name, String? city, int? capacity, String? image})? venue;
  final ({String name, int? age, String? nationality, String? photo})? coach;
  final List<JoueurEffectif> squad;
  final int? season;
  final BilanSaison? bilan;

  const FicheEquipe({this.partial = false,required this.id, required this.name, this.country, this.logo, this.founded,
      this.venue, this.coach, this.squad = const [], this.season, this.bilan});

  factory FicheEquipe.fromJson(Map<String, dynamic> j) {
    final v = j['venue'] as Map<String, dynamic>?;
    final c = j['coach'] as Map<String, dynamic>?;
    return FicheEquipe(
      partial: j['partial'] == true,
      id: (j['id'] as num).toInt(),
      name: nomEquipe(j['name'] as String? ?? ''),
      country: nomEquipeOuNul(j['country'] as String?), logo: j['logo'] as String?,
      founded: (j['founded'] as num?)?.toInt(),
      venue: v == null ? null : (name: v['name'] as String?, city: v['city'] as String?,
          capacity: (v['capacity'] as num?)?.toInt(), image: v['image'] as String?),
      coach: c == null ? null : (name: c['name'] as String? ?? '', age: (c['age'] as num?)?.toInt(),
          nationality: c['nationality'] as String?, photo: c['photo'] as String?),
      squad: [for (final p in (j['squad'] as List? ?? const [])) JoueurEffectif.fromJson(p as Map<String, dynamic>)],
      season: (j['season'] as num?)?.toInt(),
      bilan: j['seasonStats'] is Map<String, dynamic>
          ? BilanSaison.fromJson(j['seasonStats'] as Map<String, dynamic>) : null,
    );
  }
}

/// Ce qu'on sait de l'équipe en ouvrant sa fiche : nom, logo, et la
/// compétition du match d'où l'on vient (pour le bilan de la saison).
typedef ApercuEquipe = ({String nom, String? logo, String? competition});

class EquipeIntrouvable implements Exception {
  const EquipeIntrouvable();
}

final ficheEquipeProvider = FutureProvider.autoDispose
    .family<FicheEquipe, ({int id, String? competition})>((ref, p) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/equipes/${p.id}',
        queryParameters: {if (p.competition != null && p.competition!.isNotEmpty) 'league': p.competition});
    return FicheEquipe.fromJson(r.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) throw const EquipeIntrouvable();
    rethrow;
  }
});
