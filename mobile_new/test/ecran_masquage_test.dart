import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/widgets/splash_screen.dart';

/// Signalé par l'utilisateur le 18 octobre 2026 : « un cadenas s'affiche
/// quand on lance l'application, comme si c'était verrouillé ».
///
/// L'écran de masquage (contenu caché dans le sélecteur d'applications)
/// portait un grand cadenas, couvrait l'app au lancement jusqu'à la fin de
/// l'initialisation des notifications, et s'affichait même sans code PIN ni
/// biométrie — jusque dans le centre de contrôle.
///
/// `PronoWinApp` ne se monte pas dans un test (Firebase, notifications) :
/// ces gardes lisent son code.
void main() {
  final main = File('lib/main.dart').readAsStringSync()
      .split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('le masque est le logotype du démarrage, pas un cadenas', () {
    final masque = main.substring(main.indexOf('if (_privacyVisible) Positioned.fill('));
    final bloc = masque.substring(0, masque.indexOf(']),'));
    expect(bloc, contains('VueDemarrage()'));
    expect(bloc, isNot(contains('Icons.lock')));
  });

  test('au lancement, le masque part avant l\'initialisation des notifications', () {
    final lancement = main.substring(main.indexOf('addPostFrameCallback((_) async {'));
    expect(lancement.indexOf('_decouvrirSansVerrou()'), greaterThan(-1));
    expect(lancement.indexOf('_decouvrirSansVerrou()'), lessThan(lancement.indexOf('_initFCM()')));
  });

  test('en arrière-plan, le masque ne s\'affiche que si un verrou est activé', () {
    final cycle = main.substring(main.indexOf('void didChangeAppLifecycleState'));
    final branche = cycle.substring(cycle.indexOf('} else {'), cycle.indexOf('_pausedAt = DateTime.now()'));
    expect(branche, contains('_verrouActif'));
    expect(main, contains('s.pinEnabled || s.bioEnabled'));
  });

  testWidgets('le logotype s\'affiche sans cadenas', (t) async {
    await t.pumpWidget(const MaterialApp(home: VueDemarrage()));
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.byType(RichText), findsWidgets);
  });
}
