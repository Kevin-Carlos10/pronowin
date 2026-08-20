import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/widgets/bottom_nav_metrics.dart';

/// `MainScaffold` déclare `extendBody: true` : le contenu passe derrière la
/// barre de navigation. Chaque page défilante doit donc réserver au moins
/// l'empreinte de cette barre, sinon sa dernière ligne est masquée.
///
/// La page Compte réservait 80 px écrits à la main, pour une empreinte allant
/// jusqu'à 102 px sur un iPhone à barre d'accueil : 22 px de contenu passaient
/// sous la barre.
void main() {
  /// Empreinte réelle de la barre pour une encoche donnée.
  double empreinte(double insetBas) =>
      BottomNavMetrics.hauteur + BottomNavMetrics.margeBasse + insetBas;

  /// Mesure `bottomNavSpace` sous une encoche donnée.
  Future<double> mesurer(WidgetTester tester, double insetBas) async {
    late double espace;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: insetBas)),
      child: Builder(builder: (context) {
        espace = bottomNavSpace(context);
        return const SizedBox.shrink();
      }),
    ));
    return espace;
  }

  group('bottomNavSpace couvre la barre sur tous les appareils', () {
    // iPhone à barre d'accueil : 34. Android gestuel : ~24. Boutons : 0.
    for (final inset in [0.0, 24.0, 34.0, 48.0]) {
      testWidgets('encoche de $inset px', (tester) async {
        final espace = await mesurer(tester, inset);
        expect(espace, greaterThanOrEqualTo(empreinte(inset)),
            reason: 'la dernière ligne passerait sous la barre');
      });
    }

    testWidgets('l\'ancienne valeur écrite à la main était bien trop courte',
        (tester) async {
      // Le test qui aurait attrapé le défaut : 80 px ne suffisent pas dès que
      // l'encoche dépasse 12 px, ce qui est le cas de tout appareil récent.
      const ancienneValeur = 80.0;
      expect(ancienneValeur, lessThan(empreinte(34.0)),
          reason: 'sur iPhone, 80 px laissaient 22 px de contenu masqués');
      expect(ancienneValeur, lessThan(empreinte(24.0)),
          reason: 'en navigation gestuelle Android aussi');

      // Et la valeur dérivée, elle, tient.
      expect(await mesurer(tester, 34.0), greaterThan(ancienneValeur));
    });

    testWidgets('le supplément de respiration est réglable', (tester) async {
      late double serre;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Builder(builder: (context) {
          serre = bottomNavSpace(context, supplement: 0);
          return const SizedBox.shrink();
        }),
      ));
      expect(serre, empreinte(0));
    });
  });
}
