import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';

/// Bilan réel des pronostics Premium, tel que le serveur le calcule.
///
/// Remplace la phrase « Nos pronostics Premium affichent +68 % de réussite sur
/// les 30 derniers jours », qui était une constante écrite dans le code du mur
/// Premium : elle ne dépendait d'aucune donnée, ne bougeait jamais, et servait
/// pourtant d'argument pour prendre l'argent de quelqu'un.
class BilanPremium {
  final int periodeJours;
  final int pronosticsTranches;
  final int gagnes;
  final int perdus;

  /// `null` tant qu'aucun pronostic n'est tranché — un taux sans dénominateur
  /// n'existe pas, et « 0 % » se lirait comme un échec.
  final int? tauxReussite;

  /// Faux quand l'échantillon est trop mince pour qu'un taux veuille dire
  /// quelque chose. Trois pronostics gagnés font « 100 % », ce qui serait la
  /// même promesse creuse que la constante qu'on remplace.
  final bool echantillonSuffisant;

  const BilanPremium({
    required this.periodeJours,
    required this.pronosticsTranches,
    required this.gagnes,
    required this.perdus,
    required this.tauxReussite,
    required this.echantillonSuffisant,
  });

  /// Le chiffre est-il annonçable tel quel ?
  bool get affichable => echantillonSuffisant && tauxReussite != null;

  factory BilanPremium.depuisApi(Map<String, dynamic> j) => BilanPremium(
        periodeJours:       (j['periode_jours']        as num?)?.toInt() ?? 30,
        pronosticsTranches: (j['pronostics_tranches']  as num?)?.toInt() ?? 0,
        gagnes:             (j['gagnes']               as num?)?.toInt() ?? 0,
        perdus:             (j['perdus']               as num?)?.toInt() ?? 0,
        tauxReussite:       (j['taux_reussite']        as num?)?.toInt(),
        echantillonSuffisant: j['echantillon_suffisant'] == true,
      );
}

/// Le mur Premium s'affiche aussi pour un visiteur non connecté : la route est
/// publique côté serveur, et une erreur ne doit jamais empêcher la feuille de
/// s'ouvrir — elle se contente alors de ne rien annoncer.
final bilanPremiumProvider = FutureProvider<BilanPremium?>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/bilan-premium');
    return BilanPremium.depuisApi(Map<String, dynamic>.from(r.data as Map));
  } catch (_) {
    return null;
  }
});
