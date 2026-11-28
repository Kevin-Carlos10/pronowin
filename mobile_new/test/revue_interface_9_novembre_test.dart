import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/core/utils/motion.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/eclair_but.dart';

/// Revue de l'interface du 9 novembre 2026.
void main() {
  test('aucun texte sous 11 points, plus de demi-points', () {
    final motif = RegExp(r'fontSize: ?(\d+(?:\.\d+)?)[,)\s]');
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in motif.allMatches(f.readAsStringSync())) {
        final v = double.parse(m.group(1)!);
        if (v < 11 || v != v.roundToDouble()) fautes.add('${f.path} : ${m.group(1)}');
      }
    }
    expect(fautes, isEmpty, reason: 'échelle des tailles : 11 points au minimum, en points entiers');
  });

  test('les entrées animées ne se jouent qu\'à la première visite', () async {
    PremiereApparition.oublier();
    expect(PremiereApparition.valeur('essai'), isNull);
    expect(PremiereApparition.dejaVu('essai'), isFalse);
    await Future<void>.delayed(PremiereApparition.fenetre + const Duration(milliseconds: 50));
    expect(PremiereApparition.valeur('essai'), 1.0);
    expect(PremiereApparition.dejaVu('autre'), isFalse);
  });

  group('un but se voit', () {
    Widget score(int? dom, int? ext) => MaterialApp(theme: AppTheme.dark,
      home: Scaffold(body: EclairBut(dom: dom, ext: ext, child: Text('$dom - $ext'))));

    testWidgets('le total augmente : la zone s\'illumine, puis s\'éteint', (t) async {
      await t.pumpWidget(score(0, 1));
      expect(find.byKey(const Key('eclair-but')), findsNothing);
      await t.pumpWidget(score(0, 2));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('eclair-but')), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('eclair-but')), findsNothing);
    });

    testWidgets('ni au premier score connu, ni pour un but annulé', (t) async {
      await t.pumpWidget(score(null, null));
      await t.pumpWidget(score(1, 0));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('eclair-but')), findsNothing);
      await t.pumpWidget(score(0, 0));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('eclair-but')), findsNothing);
    });
  });
}
