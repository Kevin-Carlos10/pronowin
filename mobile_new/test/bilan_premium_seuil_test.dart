import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/bilan_premium_provider.dart';

/// Un bilan Premium sous 80 % ne s'affiche pas.
///
/// Le serveur décide (`affichable`) et ne publie pas le taux en dessous du
/// seuil. L'écran obéit à sa décision, sans refaire le calcul : un taux reçu
/// avec `affichable: false` reste caché, même accompagné d'un échantillon
/// suffisant.
void main() {
  BilanPremium lire(Map<String, dynamic> j) => BilanPremium.depuisApi({
        'periode_jours': 30,
        'pronostics_tranches': 20,
        'gagnes': 17,
        'perdus': 3,
        'echantillon_suffisant': true,
        ...j,
      });

  test('à 80 % ou plus, le serveur publie et l\'écran affiche', () {
    final b = lire({'taux_reussite': 85, 'affichable': true});
    expect(b.affichable, isTrue);
    expect(b.tauxReussite, 85);
  });

  test('sous 80 %, le bilan reste caché', () {
    expect(lire({'taux_reussite': null, 'affichable': false}).affichable, isFalse);
    // Même si un taux arrivait quand même : c'est `affichable` qui décide.
    expect(lire({'taux_reussite': 73, 'affichable': false}).affichable, isFalse);
  });

  test('un serveur qui ne se prononce pas ne vaut pas un accord', () {
    // Réponse d'avant le seuil de 80 % : sans `affichable`, rien ne s'affiche.
    expect(lire({'taux_reussite': 73}).affichable, isFalse);
  });

  test('un échantillon trop mince reste caché', () {
    final b = lire({
      'taux_reussite': 100,
      'affichable': true,
      'echantillon_suffisant': false,
    });
    expect(b.affichable, isFalse);
  });
}
