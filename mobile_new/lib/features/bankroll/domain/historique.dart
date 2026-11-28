/// La courbe du résultat net et le bilan de la semaine (27 novembre 2026).
///
/// L'écran les calculait sur les cinquante dernières mises simples qu'il
/// reçoit, sans les combinés ni les couvertures : la courbe ne finissait pas
/// sur le résultat net affiché au-dessus. Le serveur les calcule désormais sur
/// tout l'historique ; le calcul local ne sert plus que de repli, face à un
/// serveur qui ne les envoie pas encore.
library;

/// Une mise réglée, simple ou combinée, couverture comprise.
class ReglementLocal {
  final DateTime le;
  final double net;
  final String result;
  final bool combine;
  const ReglementLocal({required this.le, required this.net, required this.result, this.combine = false});
}

/// Un point de la courbe : le résultat net cumulé après une mise.
class PointCourbe {
  final DateTime le;
  final double cumul;
  final bool combine;
  const PointCourbe({required this.le, required this.cumul, this.combine = false});
}

class CourbeResultats {
  /// Combien de mises sont réglées en tout.
  final int reglees;

  /// Le cumul avant le premier point : zéro, sauf quand seules les dernières
  /// mises sont envoyées.
  final double depart;
  final List<PointCourbe> points;

  const CourbeResultats({required this.reglees, required this.depart, required this.points});

  /// Seules les dernières mises sont tracées.
  bool get tronquee => points.length < reglees;

  /// Le résultat net au dernier point.
  double get fin => points.isEmpty ? depart : points.last.cumul;

  factory CourbeResultats.depuisApi(Map<String, dynamic> j) => CourbeResultats(
    reglees: (j['reglees'] as num?)?.toInt() ?? 0,
    depart:  (j['cumul_depart'] as num?)?.toDouble() ?? 0,
    points:  ((j['points'] as List?) ?? const []).map((p) {
      final m = (p as Map).cast<String, dynamic>();
      return PointCourbe(
        le:      DateTime.tryParse(m['le'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        cumul:   (m['cumul'] as num).toDouble(),
        combine: m['genre'] == 'combine',
      );
    }).toList(),
  );

  factory CourbeResultats.locale(List<ReglementLocal> reglements) {
    final tries = [...reglements]..sort((a, b) => a.le.compareTo(b.le));
    var cumul = 0.0;
    return CourbeResultats(
      reglees: tries.length,
      depart: 0,
      points: [
        for (final r in tries) PointCourbe(le: r.le, cumul: cumul += r.net, combine: r.combine),
      ],
    );
  }
}

/// Les sept derniers jours, d'après la date du règlement.
class BilanSemaine {
  final int paris, gagnes, perdus, rembourses, combines, combinesGagnes;

  /// Le résultat net de la semaine, combinés et couvertures compris.
  final double profit;

  const BilanSemaine({
    this.paris = 0, this.gagnes = 0, this.perdus = 0, this.rembourses = 0,
    this.combines = 0, this.combinesGagnes = 0, this.profit = 0,
  });

  bool get vide => paris == 0 && combines == 0;

  factory BilanSemaine.depuisApi(Map<String, dynamic> j) => BilanSemaine(
    paris:          (j['paris'] as num?)?.toInt() ?? 0,
    gagnes:         (j['gagnes'] as num?)?.toInt() ?? 0,
    perdus:         (j['perdus'] as num?)?.toInt() ?? 0,
    rembourses:     (j['rembourses'] as num?)?.toInt() ?? 0,
    combines:       (j['combines'] as num?)?.toInt() ?? 0,
    combinesGagnes: (j['combines_gagnes'] as num?)?.toInt() ?? 0,
    profit:         (j['profit'] as num?)?.toDouble() ?? 0,
  );

  factory BilanSemaine.locale(List<ReglementLocal> reglements, DateTime maintenant) {
    final depuis = maintenant.subtract(const Duration(days: 7));
    final semaine = reglements.where((r) => !r.le.isBefore(depuis)).toList();
    final paris = semaine.where((r) => !r.combine).toList();
    final combines = semaine.where((r) => r.combine).toList();
    return BilanSemaine(
      paris:          paris.length,
      gagnes:         paris.where((r) => r.result == 'WIN').length,
      perdus:         paris.where((r) => r.result == 'LOSS').length,
      rembourses:     paris.where((r) => r.result == 'PUSH').length,
      combines:       combines.length,
      combinesGagnes: combines.where((r) => r.result == 'WIN').length,
      profit:         semaine.fold<double>(0, (n, r) => n + r.net),
    );
  }
}
