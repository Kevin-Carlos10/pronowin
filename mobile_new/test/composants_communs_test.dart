import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/utils/messages.dart';
import 'package:pronowin/shared/widgets/main_scaffold.dart';
import 'package:pronowin/shared/widgets/pw_button.dart';

import 'aides/code_seul.dart';

/// Les composants que tous les écrans partagent : bouton principal, messages,
/// barre de navigation. Un défaut ici se répète partout.
void main() {
  Widget hote(Widget enfant, {ThemeData? theme, double echelle = 1, double largeur = 360}) =>
      MediaQuery(
        data: MediaQueryData(size: Size(largeur, 800), textScaler: TextScaler.linear(echelle)),
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          localizationsDelegates: const [AppStrings.delegate],
          home: Scaffold(body: Center(child: SizedBox(width: largeur - 32, child: enfant))),
        ),
      );

  group('bouton principal', () {
    testWidgets('lecteur d\'écran : un bouton, nommé, activable', (t) async {
      final semantique = t.ensureSemantics();
      await t.pumpWidget(hote(PwButton(label: 'Continuer', onPressed: () {})));
      // C'était un `GestureDetector` nu : rien n'annonçait un bouton.
      expect(t.getSemantics(find.byType(PwButton)),
          isSemantics(label: 'Continuer', isButton: true, hasEnabledState: true, isEnabled: true));
      semantique.dispose();
    });

    testWidgets('désactivé, il le dit', (t) async {
      final semantique = t.ensureSemantics();
      await t.pumpWidget(hote(const PwButton(label: 'Continuer')));
      expect(t.getSemantics(find.byType(PwButton)),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
      semantique.dispose();
    });

    testWidgets('le dégradé est celui des boutons lisibles', (t) async {
      await t.pumpWidget(hote(PwButton(label: 'Continuer', onPressed: () {})));
      final boite = t.widget<DecoratedBox>(find.descendant(
          of: find.byType(PwButton), matching: find.byType(DecoratedBox)).first);
      final degrade = (boite.decoration as BoxDecoration).gradient as LinearGradient;
      // Orange → jaune : blanc à 2,03:1 côté jaune.
      expect(degrade.colors, AppColors.degradeBouton);
    });

    testWidgets('texte à 200 %, libellé long : il grandit au lieu de rogner', (t) async {
      await t.pumpWidget(hote(
          PwButton(label: 'Créer un compte gratuit pour continuer', onPressed: () {}),
          echelle: 2, largeur: 320));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(PwButton)).height, greaterThan(52),
          reason: 'la hauteur fixe de 52 coupait le libellé agrandi');
    });
  });

  group('messages', () {
    for (final (type, fond) in [
      (TypeMessage.succes, AppColors.fondSucces),
      (TypeMessage.erreur, AppColors.fondErreur),
      (TypeMessage.alerte, AppColors.fondAlerte),
    ]) {
      for (final (nomTheme, theme) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
        testWidgets('${type.name} · $nomTheme : fond plein lisible, icône, texte blanc', (t) async {
          await t.pumpWidget(hote(Builder(builder: (context) => TextButton(
              onPressed: () => afficherMessage(context, 'Enregistré', type: type),
              child: const Text('go'))), theme: theme));
          await t.tap(find.text('go'));
          await t.pump();
          final barre = t.widget<SnackBar>(find.byType(SnackBar));
          expect(barre.backgroundColor, fond,
              reason: 'le même fond dans les deux thèmes : le vert vif du sombre faisait 2,28:1');
          expect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)), findsOneWidget,
              reason: 'le type ne repose pas sur la seule couleur');
          expect(t.widget<Text>(find.text('Enregistré')).style?.color, Colors.white);
        });
      }
    }

    testWidgets('un message remplace le précédent', (t) async {
      await t.pumpWidget(hote(Builder(builder: (context) => TextButton(
          onPressed: () {
            afficherMessage(context, 'Un');
            afficherMessage(context, 'Deux');
          },
          child: const Text('go')))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Deux'), findsOneWidget);
      expect(find.text('Un'), findsNothing);
    });

    test('aucun écran ne construit son propre SnackBar', () {
      // Une quarantaine étaient faits à la main, chacun avec sa couleur.
      final fautes = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('messages.dart')) continue;
        if (RegExp(r'\bSnackBar\(').hasMatch(f.readAsStringSync().pipeCodeSeul())) fautes.add(f.path);
      }
      expect(fautes, isEmpty, reason: 'passer par afficherMessage');
    });
  });

  group('barre de navigation', () {
    for (final largeur in [320.0, 360.0]) {
      for (final echelle in [1.0, 1.8]) {
        testWidgets('$largeur px · texte ${(echelle * 100).round()} % : rien ne déborde', (t) async {
          t.view.physicalSize = Size(largeur * 2, 800 * 2);
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const [AppStrings.delegate],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
              child: child!,
            ),
            home: Scaffold(bottomNavigationBar: barreNavigationSeule()),
          ));
          // Cinq cases de 60 px et 24 de marges : 324 px demandés à 320.
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  test('paywall et écran de mise à jour : toujours sombres, et assumés', () {
    // Décision produit (2026-10-01) : ces deux écrans restent sombres en
    // thème clair. Assumé ne veut pas dire hybride : leur contenu lit le
    // thème sombre, sinon les couleurs d'état passent à leurs variantes pour
    // fond blanc sur un fond de stade.
    for (final (fichier, ancre) in [
      ('lib/features/abonnement/presentation/pages/activer_premium_page.dart',
          'SurfaceSombre(builder: (context) => _PaywallPage('),
      ('lib/core/widgets/ecran_mise_a_jour.dart', 'SurfaceSombre(builder: (context) => PopScope('),
    ]) {
      expect(File(fichier).readAsStringSync().pipeCodeSeul(), contains(ancre), reason: fichier);
    }
  });
}
