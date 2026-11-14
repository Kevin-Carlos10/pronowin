import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';

/// Les sélections nationales en français.
///
/// Vu sur iPhone : « France gagne » au-dessus de « Belgium », « Belgique
/// gagne » dans l'historique sous « Belgium », « Norway », « Türkiye ».
void main() {
  test('les pays du fournisseur, en français', () {
    expect(nomEquipe('Belgium'), 'Belgique');
    expect(nomEquipe('Türkiye'), 'Turquie');
    expect(nomEquipe('Rep. Of Ireland'), 'Irlande');
    expect(nomEquipe('Cape Verde Islands'), 'Cap-Vert');
    expect(nomEquipe('Ivory Coast'), "Côte d'Ivoire");
    expect(nomEquipe('Congo DR'), 'RD Congo');
  });

  test('un pays déjà écrit en français, ou un club, reste tel quel', () {
    expect(nomEquipe('France'), 'France');
    expect(nomEquipe('Burkina Faso'), 'Burkina Faso');
    expect(nomEquipe('Real Madrid'), 'Real Madrid');
    expect(nomEquipe('Manchester City'), 'Manchester City');
  });

  test('la catégorie suit le pays', () {
    expect(nomEquipe('Spain U21'), 'Espagne U21');
    expect(nomEquipe('Germany W'), 'Allemagne W');
  });

  group('dans un libellé de pronostic', () {
    test('le nom anglais recopié par le panneau est traduit', () {
      expect(traduireEquipesDansLibelle('Norway gagne', ['Portugal', 'Norway']), 'Norvège gagne');
      expect(MatchEntity.applyTeamNames('Belgium gagne', homeTeam: 'Belgique', awayTeam: 'France'),
          'Belgique gagne');
    });

    test('seules les deux équipes du match sont touchées, jamais un joueur', () {
      // « Jordan » est aussi un pays : il ne joue pas ce match.
      expect(traduireEquipesDansLibelle('Jordan Henderson marque — England', ['England', 'Wales']),
          'Jordan Henderson marque — Angleterre');
    });

    test('un mot qui contient le nom n\'est pas touché', () {
      expect(traduireEquipesDansLibelle('Chadwick marque', ['Chad', 'Mali']), 'Chadwick marque');
    });
  });
}
