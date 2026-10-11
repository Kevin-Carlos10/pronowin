import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/verrou_pronostic.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
void main() {
  test('une réponse masquée reste verrouillée même avec Premium local', () {
    for (final termine in [false, true]) {
      expect(estVerrouille(contenuMasque: true, estPremium: true,
        matchTermine: termine, utilisateurPremium: true), isTrue);
    }
  });
  test('une confiance absente ne devient pas une estimation à 10%', () {
    final json = <String, dynamic>{'id':'m', 'league':'Premier League',
      'home_team':'Arsenal', 'away_team':'Leeds', 'match_date':'2026-10-10T11:30:00Z',
      'locked':true, 'is_premium':true, 'confidence_score':null, 'confidence_pct':null};
    final match = MatchModel.fromJson(json);
    expect(match.pourcentageConfiance, 0);
    expect(MatchModel.fromJson(match.toJson()).isLocked, isTrue);
    expect(MatchModel.fromJson({...json, 'confidence_score':5, 'confidence_pct':85}).pourcentageConfiance,85);
  });
}
