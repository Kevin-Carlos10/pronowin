import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// Sur Lask Linz – Celtic, le modèle externe donnait 0 % à Lask Linz et 100 %
/// de l'avantage à Celtic sur les cinq critères. Lask Linz a gagné 4–1.
///
/// L'écran affichait « < 1 % » — un adoucissement de libellé qui laissait
/// intacte l'affirmation. Le serveur signale désormais ces sorties, et l'écran
/// doit se taire.
void main() {
  Map<String, dynamic> reponse({
    bool? exploitable,
    Map<String, dynamic>? percent,
    List<Map<String, dynamic>> axes = const [],
  }) {
    final j = <String, dynamic>{
      'advice': 'Vainqueur : Celtic',
      'percent': percent,
      'comparisons': axes,
      'clean_sheet': {'home': 0, 'away': 0},
      'form': {'home': null, 'away': null},
      'goals_by_minute': {'home': null, 'away': null},
      'home_team': 'Lask Linz',
      'away_team': 'Celtic',
    };
    // Champ omis quand `exploitable` est nul : c'est ainsi qu'on simule une
    // réponse d'un serveur antérieur au drapeau.
    if (exploitable != null) j['modele_exploitable'] = exploitable;
    return j;
  }

  const axe = {'label': 'Forme', 'home': 0, 'away': 100};

  test('une sortie signalée inexploitable est portée jusqu\'à l\'écran', () {
    final m = MatchInsights.fromJson(reponse(exploitable: false, axes: [axe]));
    expect(m.modeleExploitable, isFalse);
  });

  test('une sortie exploitable reste affichable', () {
    final m = MatchInsights.fromJson(reponse(
      exploitable: true,
      percent: {'home': 45, 'draw': 45, 'away': 10},
      axes: [{'label': 'Forme', 'home': 64, 'away': 36}],
    ));
    expect(m.modeleExploitable, isTrue);
    expect(m.percentHome, 45);
  });

  // Le serveur vide les champs quand il refuse : l'écran ne doit surtout pas
  // en déduire « 0 % pour tout le monde ».
  test('les champs vidés ne se lisent pas comme des zéros crédibles', () {
    final m = MatchInsights.fromJson(reponse(exploitable: false, axes: [axe]));
    expect(m.advice, isNotNull); // le serveur le vide, pas le parseur
    expect(m.percentHome, 0);
    expect(m.modeleExploitable, isFalse,
      reason: 'c\'est le drapeau qui décide, pas les valeurs — trois zéros '
              'sans drapeau resteraient indiscernables d\'un vrai 0-0-0');
  });

  // Une version antérieure du serveur ne renvoie pas le champ : on ne doit pas
  // faire disparaître la section partout d'un coup.
  test('un serveur plus ancien reste compatible', () {
    final m = MatchInsights.fromJson(reponse(
      percent: {'home': 40, 'draw': 30, 'away': 30},
      axes: [{'label': 'Forme', 'home': 55, 'away': 45}],
    ));
    expect(m.modeleExploitable, isTrue);
  });
}
