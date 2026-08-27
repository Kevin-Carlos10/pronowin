import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/shared/widgets/confidence_indicator.dart';

/// La confiance s'affiche en pourcentage, partout.
///
/// `ConfidenceIndicator` rendait au choix un pourcentage ou une jauge de cinq
/// segments, selon un drapeau que chaque appelant réglait comme il l'entendait.
/// Le même score apparaissait donc « 80 % » sur l'accueil et « ▪▪▪▪▫ » sur la
/// carte juste en dessous — sans qu'aucun des deux ne dise combien vaut un
/// segment.
///
/// Un pourcentage se compare, se retient, et se recopie dans une conversation.
/// Une jauge, non.
void main() {
  Future<void> rendre(WidgetTester tester, Widget enfant) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: enfant)),
    ));
    // L'animation compte de 0 jusqu'à la valeur : on la laisse finir.
    await tester.pumpAndSettle();
  }

  group('le pourcentage est affiché, quel que soit le score', () {
    for (final score in [1, 2, 3, 4, 5]) {
      testWidgets('score $score', (tester) async {
        await rendre(tester, ConfidenceIndicator(score: score));

        final attendu = MatchEntity.percentForConfidence(score);
        expect(find.text('$attendu %'), findsOneWidget);
      });
    }

    testWidgets('un score hors bornes ne casse rien', (tester) async {
      // L'API pourrait renvoyer 0 ou 7 : la conversion borne déjà, l'affichage
      // doit suivre sans exception.
      await rendre(tester, const ConfidenceIndicator(score: 0));
      expect(find.textContaining('%'), findsOneWidget);

      await rendre(tester, const ConfidenceIndicator(score: 9));
      expect(find.textContaining('%'), findsOneWidget);
    });
  });

  group('le libellé reste optionnel', () {
    testWidgets('affiché par défaut', (tester) async {
      await rendre(tester, const ConfidenceIndicator(score: 4));

      expect(find.text(MatchEntity.labelForConfidence(4)), findsOneWidget);
      expect(find.text('90 %'), findsOneWidget);
    });

    testWidgets('masqué sur demande, le pourcentage subsiste', (tester) async {
      await rendre(tester,
          const ConfidenceIndicator(score: 4, showLabel: false));

      expect(find.text(MatchEntity.labelForConfidence(4)), findsNothing);
      expect(find.text('90 %'), findsOneWidget);
    });
  });

  group('plus aucune jauge à segments', () {
    final source = File('lib/shared/widgets/confidence_indicator.dart')
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join('\n');

    test('le drapeau qui laissait choisir a disparu', () {
      // C'est lui qui permettait à deux écrans voisins de ne pas s'accorder.
      expect(source.contains('asPercent'), isFalse);
    });

    test('les cinq segments ne sont plus construits', () {
      expect(source.contains('List.generate(5'), isFalse);
      expect(source.contains('remplissage'), isFalse);
    });

    test('aucun appelant ne réclame une largeur de jauge', () {
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)
          .whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        final i = src.indexOf('ConfidenceIndicator(');
        if (i == -1) continue;
        // La largeur n'a de sens que pour une jauge : sa présence signalerait
        // un retour en arrière.
        if (RegExp(r'ConfidenceIndicator\([^)]*width:').hasMatch(src)) {
          fautifs.add(f.path.replaceAll(RegExp(r'\\'), '/'));
        }
      }
      expect(fautifs, isEmpty);
    });
  });
}
