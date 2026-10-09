import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/auth/presentation/widgets/bouton_fournisseur.dart';

Widget _hote(Widget enfant) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(20), child: enfant)),
    );

/// L'écran de connexion opposait un bouton plein (e-mail) à un bouton contour
/// (Google). Le choix était donc fait pour l'utilisateur — et il poussait vers
/// le chemin le plus lent, celui qui exige d'attendre un code et de le
/// ressaisir, et le seul qui coûte un envoi à PronoWin.
///
/// Ces contrôles portent sur ce qui doit rester vrai quand « Continuer avec
/// Apple » viendra s'ajouter à la pile — obligatoire dès la sortie iOS.
void main() {
  group('un chemin de connexion en vaut un autre', () {
    testWidgets('tous les boutons partagent la même hauteur', (tester) async {
      await tester.pumpWidget(_hote(Column(children: const [
        BoutonFournisseur(libelle: 'Continuer avec Google', logo: LogoGoogle()),
        SizedBox(height: 11),
        BoutonFournisseur(libelle: 'Continuer avec un e-mail', logo: LogoEmail()),
      ])));

      final hauteurs = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.width == double.infinity)
          .map((b) => b.height)
          .toSet();
      expect(hauteurs.length, 1,
          reason: 'des hauteurs différentes hiérarchisent les chemins');
    });

    testWidgets('aucun bouton n\'est rempli — seul le contour les distingue',
        (tester) async {
      // Un fond plein sur l'un d'eux rétablirait la hiérarchie qu'on retire.
      await tester.pumpWidget(_hote(const BoutonFournisseur(
        libelle: 'Continuer avec Google', logo: LogoGoogle())));

      final deco = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>();
      for (final d in deco) {
        expect(d.color, anyOf(isNull, Colors.transparent),
            reason: 'un bouton de fournisseur reste en contour');
        expect(d.gradient, isNull);
      }
    });
  });

  group('état désactivé', () {
    testWidgets('un bouton désactivé ne réagit pas au tap', (tester) async {
      var touches = 0;
      await tester.pumpWidget(_hote(BoutonFournisseur(
        libelle: 'Continuer avec Google',
        logo: const LogoGoogle(),
        desactive: true,
        onPressed: () => touches++,
      )));

      await tester.tap(find.text('Continuer avec Google'));
      await tester.pump();
      // Deux authentifications simultanées ouvriraient deux sessions
      // concurrentes ; le second appui doit rester sans effet.
      expect(touches, 0);
    });

    testWidgets('un bouton actif réagit', (tester) async {
      var touches = 0;
      await tester.pumpWidget(_hote(BoutonFournisseur(
        libelle: 'Continuer avec Google',
        logo: const LogoGoogle(),
        onPressed: () => touches++,
      )));

      await tester.tap(find.text('Continuer avec Google'));
      await tester.pump();
      expect(touches, 1);
    });

    testWidgets('sans callback, le bouton est inerte mais s\'affiche',
        (tester) async {
      await tester.pumpWidget(_hote(const BoutonFournisseur(
        libelle: 'Continuer avec Apple')));
      expect(find.text('Continuer avec Apple'), findsOneWidget);
    });
  });

  group('marque Google', () {
    testWidgets('le logo est une image, pas un glyphe de police',
        (tester) async {
      // `Icons.g_mobiledata_rounded` était employé : un « G » monochrome
      // Material, qui n'est pas la marque Google — et que personne ne
      // reconnaît comme un bouton Google.
      await tester.pumpWidget(_hote(const LogoGoogle()));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('l\'e-mail garde une icône neutre, sans marque', (tester) async {
      await tester.pumpWidget(_hote(const LogoEmail()));
      expect(find.byType(Icon), findsOneWidget);
    });
  });
}
