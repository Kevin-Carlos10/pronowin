// La durée d'un tutoriel, telle que l'écran l'affiche.
//
// « 9min » s'écrivait collé, et un tutoriel sans durée connue affichait
// « ⏱ — » (vidéo du 5 octobre 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/tutoriels/domain/entities/tutorial_entity.dart';

TutorialEntity _tuto(int secondes) => TutorialEntity(
      id: 't', title: 'Value bet', description: '', level: TutorialLevel.beginner,
      category: 'strategie', durationSeconds: secondes);

void main() {
  test('les minutes, séparées par une espace insécable', () {
    expect(_tuto(9 * 60 + 40).durationText, '9 min');
    expect(_tuto(59 * 60).durationText, '59 min');
  });

  test('au-delà d\'une heure, les minutes sur deux chiffres', () {
    expect(_tuto(65 * 60).durationText, '1 h 05');
    expect(_tuto(2 * 3600 + 30 * 60).durationText, '2 h 30');
  });

  test('une durée inconnue ne s\'affiche pas', () {
    expect(_tuto(0).aUneDuree, isFalse);
    expect(_tuto(45).aUneDuree, isFalse);
    expect(_tuto(60).aUneDuree, isTrue);
  });
}
