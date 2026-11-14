import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/noms_equipes.dart';

/// Équipes et joueurs pour la recherche (7 novembre 2026) : la recherche ne
/// trouvait que des matchs, Sofascore et FotMob trouvent aussi les équipes et
/// les joueurs, et ouvrent leur fiche.
class EquipeTrouvee {
  final int id;
  final String nom;
  final String? logo, competition;
  const EquipeTrouvee({required this.id, required this.nom, this.logo, this.competition});
}

class JoueurTrouve {
  final int id;
  final String nom;
  final String? photo, poste, nationalite;
  final int? age;
  const JoueurTrouve({required this.id, required this.nom, this.photo, this.poste, this.nationalite, this.age});
}

class ResultatsRecherche {
  final List<EquipeTrouvee> equipes;
  final List<JoueurTrouve> joueurs;
  const ResultatsRecherche({this.equipes = const [], this.joueurs = const []});
  static const vide = ResultatsRecherche();
  bool get estVide => equipes.isEmpty && joueurs.isEmpty;
}

/// Attente avant d'interroger le serveur : la recherche des joueurs coûte une
/// requête au fournisseur par terme, pas une par lettre tapée.
const delaiRecherche = Duration(milliseconds: 350);

/// Vide en deçà de deux lettres, ou si le serveur ne répond pas : ces
/// résultats complètent ceux des matchs, ils ne doivent pas les masquer.
final rechercheEquipesJoueursProvider =
    FutureProvider.autoDispose.family<ResultatsRecherche, String>((ref, terme) async {
  final t = terme.trim();
  if (t.length < 2) return ResultatsRecherche.vide;
  var abandonnee = false;
  ref.onDispose(() => abandonnee = true);
  await Future<void>.delayed(delaiRecherche);
  if (abandonnee) return ResultatsRecherche.vide;
  try {
    final r = await ref.read(dioProvider).get('/pronostics/recherche', queryParameters: {'q': t});
    final d = r.data as Map;
    return ResultatsRecherche(
      equipes: [
        for (final e in (d['equipes'] as List? ?? const []))
          if (e is Map && e['id'] is num)
            EquipeTrouvee(id: (e['id'] as num).toInt(), nom: nomEquipe(e['nom'] as String? ?? ''),
              logo: e['logo'] as String?, competition: e['competition'] as String?),
      ],
      joueurs: [
        for (final j in (d['joueurs'] as List? ?? const []))
          if (j is Map && j['id'] is num)
            JoueurTrouve(id: (j['id'] as num).toInt(), nom: j['nom'] as String? ?? '',
              photo: j['photo'] as String?, poste: j['poste'] as String?,
              nationalite: j['nationalite'] as String?, age: (j['age'] as num?)?.toInt()),
      ],
    );
  } on DioException {
    return ResultatsRecherche.vide;
  }
});
