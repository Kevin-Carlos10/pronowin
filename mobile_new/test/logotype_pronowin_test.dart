import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/shared/widgets/logotype_pronowin.dart';

/// Le logotype était réécrit à la main à six endroits, et les copies avaient
/// déjà divergé : `w800` ici, `w900` là, un `letterSpacing` de -1, de -0.5 ou
/// absent, et un « Prono » tantôt figé en blanc — donc invisible en thème
/// clair — tantôt lié au thème.
///
/// Rien de tout cela ne casse : la marque s'affiche simplement d'une façon
/// différente à chaque écran.
void main() {
  Widget hote(Widget enfant, {Brightness clarte = Brightness.dark}) => MaterialApp(
        theme: clarte == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: Center(child: enfant)),
      );

  List<TextSpan> fragments(WidgetTester t) {
    final rt = t.widget<RichText>(find.byType(RichText));
    return (rt.text as TextSpan).children!.cast<TextSpan>();
  }

  group('la marque s\'écrit toujours pareil', () {
    testWidgets('deux fragments : « Prono » puis « Win »', (t) async {
      await t.pumpWidget(hote(const LogotypePronoWin()));
      final f = fragments(t);
      expect(f.map((s) => s.text).toList(), ['Prono', 'Win']);
    });

    testWidgets('« Win » porte toujours la couleur d\'accent', (t) async {
      // C'est le seul élément qui fait reconnaître la marque d'un coup d'œil.
      for (final c in [Brightness.dark, Brightness.light]) {
        await t.pumpWidget(hote(const LogotypePronoWin(), clarte: c));
        expect(fragments(t)[1].style!.color, AppColors.primary);
      }
    });

    testWidgets('la graisse ne varie pas avec la taille', (t) async {
      for (final taille in [18.0, 24.0, 30.0]) {
        await t.pumpWidget(hote(LogotypePronoWin(taille: taille)));
        final rt = t.widget<RichText>(find.byType(RichText));
        expect((rt.text as TextSpan).style!.fontWeight, FontWeight.w900);
      }
    });
  });

  group('lisibilité dans les deux thèmes', () {
    testWidgets('« Prono » suit le thème par défaut', (t) async {
      await t.pumpWidget(hote(const LogotypePronoWin(), clarte: Brightness.light));
      final couleur = fragments(t)[0].style!.color!;
      // Un blanc figé disparaîtrait sur fond clair — c'est ce que faisaient
      // trois des six copies.
      expect(couleur, isNot(Colors.white));
      expect(couleur.computeLuminance(), lessThan(0.5));
    });

    testWidgets('surFondSombre force le blanc, et seulement alors', (t) async {
      await t.pumpWidget(hote(const LogotypePronoWin(surFondSombre: true),
          clarte: Brightness.light));
      expect(fragments(t)[0].style!.color, Colors.white);
    });
  });
}
