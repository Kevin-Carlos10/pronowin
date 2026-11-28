import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/domain/entities/avis_compares.dart';

/// Le calcul et l'analyste, reliés par une phrase.
///
/// Vu sur France – Belgique : « indice de confiance 85 % » sur le pronostic,
/// « probabilité de succès 58 % » dans l'analyse, sans un mot pour les relier.
void main() {
  test('le cas de la capture : le calcul est plus prudent, et le dit', () {
    const a = AvisCompares(calcul: 58, analyste: 85);
    expect(a.concordants, isFalse);
    expect(a.calculPlusPrudent, isTrue);
    expect(a.phrase, contains('plus prudent'));
    expect(a.phrase, contains('58 % contre 85 %'));
  });

  test('un calcul plus confiant que l\'analyste', () {
    const a = AvisCompares(calcul: 80, analyste: 60);
    expect(a.calculPlusPrudent, isFalse);
    expect(a.phrase, contains('plus confiant'));
  });

  test('sous quinze points d\'écart, les deux avis concordent', () {
    expect(const AvisCompares(calcul: 72, analyste: 85).concordants, isTrue);
    expect(const AvisCompares(calcul: 72, analyste: 85).phrase, contains('rejoint'));
    expect(const AvisCompares(calcul: 70, analyste: 85).concordants, isFalse);
  });
}
