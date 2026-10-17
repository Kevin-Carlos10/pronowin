/// Chrono d'un match en direct, à la seconde, comme sur Sofascore.
///
/// Demande de l'utilisateur (17 octobre 2026). La fiche n'affichait que la
/// minute (« 39' »), relevée toutes les 30 s. API-Football donne l'heure exacte
/// du début de chaque mi-temps (`periods`) : le téléphone en déduit le temps
/// de jeu à la seconde et le fait avancer lui-même entre deux relevés.
///
/// Garde-fou : si le chrono calculé s'écarte de plus de [ecartToleree] de la
/// minute que publie la source (horodatage faux, horloge du téléphone
/// déréglée), on revient à la minute seule. Un chrono faux à la seconde vaut
/// moins qu'une minute juste.
library;

/// Ce que montre le chrono.
enum EtatChrono {
  /// Mi-temps en cours, temps connu à la seconde : « 67:23 ».
  aLaSeconde,

  /// Temps connu à la minute seulement : « 67' » (prolongations, horodatage
  /// absent ou incohérent).
  aLaMinute,

  /// Pause entre les deux mi-temps.
  miTemps,

  /// Pause avant les prolongations.
  pause,

  /// Séance de tirs au but.
  tirsAuBut,

  /// Match suspendu ou interrompu.
  interrompu,

  /// En direct, sans aucune indication de temps.
  inconnu,
}

class ChronoMatch {
  final EtatChrono etat;

  /// Temps de jeu en secondes depuis le coup d'envoi ([EtatChrono.aLaSeconde]).
  final int? secondes;

  /// Minute de jeu, quand elle est connue.
  final int? minute;

  /// Temps additionnel annoncé, en minutes, une fois qu'on est dedans.
  final int? additionnel;

  const ChronoMatch(this.etat, {this.secondes, this.minute, this.additionnel});

  /// « 67:23 » : minutes sur deux chiffres au moins, secondes sur deux.
  String get texteSecondes {
    final s = secondes ?? 0;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is ChronoMatch && other.etat == etat && other.secondes == secondes &&
      other.minute == minute && other.additionnel == additionnel;

  @override
  int get hashCode => Object.hash(etat, secondes, minute, additionnel);

  @override
  String toString() => 'ChronoMatch($etat, secondes: $secondes, minute: $minute, +$additionnel)';
}

/// Écart toléré entre le chrono calculé et la minute de la source.
const ecartToleree = Duration(minutes: 4);

/// Calcule le chrono à l'instant [maintenant].
///
/// [phase] : statut court d'API-Football (`1H`, `HT`, `2H`, `ET`, `BT`, `P`,
/// `SUSP`, `INT`, `LIVE`). [elapsed] : minute publiée. [extra] : temps
/// additionnel annoncé. [debut1] / [debut2] : début de chaque mi-temps.
ChronoMatch chronoMatch({
  String? phase,
  int? elapsed,
  int? extra,
  DateTime? debut1,
  DateTime? debut2,
  required DateTime maintenant,
}) {
  switch (phase?.toUpperCase()) {
    case 'HT':
      return const ChronoMatch(EtatChrono.miTemps);
    case 'BT':
      return const ChronoMatch(EtatChrono.pause);
    case 'P':
      return const ChronoMatch(EtatChrono.tirsAuBut);
    case 'SUSP':
    case 'INT':
      return ChronoMatch(EtatChrono.interrompu, minute: elapsed);
    case '1H':
      return _mitemps(base: 0, fin: 45, debut: debut1, elapsed: elapsed, extra: extra, maintenant: maintenant);
    case '2H':
      return _mitemps(base: 45, fin: 90, debut: debut2, elapsed: elapsed, extra: extra, maintenant: maintenant);
  }
  // Prolongations : API-Football ne date pas leur début. Phase inconnue
  // (`LIVE`, absente) : la minute si on l'a.
  if (elapsed != null) {
    return ChronoMatch(EtatChrono.aLaMinute, minute: elapsed,
        additionnel: phase?.toUpperCase() == 'ET' && elapsed >= 120 ? _positif(extra) : null);
  }
  return const ChronoMatch(EtatChrono.inconnu);
}

ChronoMatch _mitemps({
  required int base,
  required int fin,
  required DateTime? debut,
  required int? elapsed,
  required int? extra,
  required DateTime maintenant,
}) {
  ChronoMatch aLaMinute() => elapsed == null
      ? const ChronoMatch(EtatChrono.inconnu)
      : ChronoMatch(EtatChrono.aLaMinute, minute: elapsed,
          additionnel: elapsed >= fin ? _positif(extra) : null);

  if (debut == null) return aLaMinute();
  final ecoule = maintenant.difference(debut);
  // Horloge du téléphone en retard sur le coup d'envoi : on ne remonte pas
  // le temps, la mi-temps commence à 0.
  final secondes = base * 60 + (ecoule.isNegative ? 0 : ecoule.inSeconds);
  if (elapsed != null &&
      (secondes - elapsed * 60).abs() > ecartToleree.inSeconds + 60) {
    return aLaMinute();
  }
  final minute = secondes ~/ 60 + 1;
  return ChronoMatch(EtatChrono.aLaSeconde,
      secondes: secondes,
      minute: minute,
      additionnel: secondes >= fin * 60 ? _positif(extra) : null);
}

int? _positif(int? v) => v != null && v > 0 ? v : null;

/// Horodatage Unix en secondes → date, ou null.
DateTime? depuisSecondesUnix(Object? v) =>
    v is int && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true) : null;
