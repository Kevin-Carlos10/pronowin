import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/widgets/chiffres_ios.dart';

/// L'effet d'iOS au changement d'un compte à rebours (retour de l'utilisateur
/// du 17 octobre 2026) : seul le chiffre qui change bascule, flouté ; les
/// autres ne bougent pas.
void main() {
  Future<void> afficher(WidgetTester t, String texte, {bool reduit = false}) => t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduit),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: ChiffresIos(texte, style: const TextStyle(fontSize: 22))),
          ),
        ),
      );

  testWidgets('38 → 37 : seul le chiffre des unités bascule, flouté', (t) async {
    await afficher(t, '38');
    await afficher(t, '37');
    await t.pump(const Duration(milliseconds: 80));
    expect(find.text('8'), findsOneWidget, reason: "l'ancien chiffre sort");
    expect(find.text('7'), findsOneWidget, reason: 'le nouveau entre');
    expect(find.text('3'), findsOneWidget, reason: 'le chiffre des dizaines ne bouge pas');
    expect(find.byType(ImageFiltered), findsWidgets, reason: 'flou pendant la bascule');

    await t.pump(ChiffresIos.duree);
    expect(find.text('8'), findsNothing);
    expect(find.text('7'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing, reason: 'net une fois arrivé');
  });

  testWidgets('40 → 39 : les deux chiffres basculent', (t) async {
    await afficher(t, '40');
    await afficher(t, '39');
    await t.pump(const Duration(milliseconds: 80));
    for (final c in ['4', '0', '3', '9']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  testWidgets('animations réduites : changement immédiat, sans flou', (t) async {
    await afficher(t, '38', reduit: true);
    await afficher(t, '37', reduit: true);
    await t.pump();
    expect(find.text('8'), findsNothing);
    expect(find.text('7'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
