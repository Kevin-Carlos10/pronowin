import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/router/navigation_keys.dart';
import 'package:pronowin/core/services/version_service.dart';

/// D'où la fenêtre de mise à jour est ouverte.
///
/// Le 14 septembre 2026, un émulateur en 1.0.4 face à un seuil minimal fixé à
/// 1.0.9 n'a rien affiché. Le serveur publiait les bonnes valeurs, l'émulateur
/// appelait bien `GET /config`, la comparaison de versions était juste, la
/// fenêtre était correctement verrouillée — et rien ne s'affichait.
///
/// `check()` recevait le `BuildContext` de l'État qui l'appelle, dans
/// `main.dart`. Or cet État **construit** le `MaterialApp.router` : son
/// contexte se situe au-dessus de lui, donc au-dessus de tout `Navigator` et
/// de toute `MaterialLocalizations`. `showDialog` remonte l'arbre, ne trouve
/// rien, et lève. L'exception tombait dans le `catch (_)` vide de `check()`.
///
/// Cela valait pour les deux canaux et pour l'avis de maintenance : depuis
/// l'origine, aucune de ces fenêtres n'avait jamais pu s'afficher.
///
/// ── Pourquoi les tests existants ne l'ont pas vu ─────────────────────────
///
/// `mise_a_jour_obligatoire_test.dart` monte un `MaterialApp` puis ouvre la
/// fenêtre depuis un `Builder` placé **dessous**. Il éprouvait donc
/// parfaitement le comportement de la fenêtre, depuis un contexte que
/// l'application n'a jamais eu. C'est la raison pour laquelle ce banc-ci monte
/// la forme réelle de `main.dart` plutôt qu'un écran de test commode.
void main() {
  testWidgets('la clé du navigateur racine ouvre la fenêtre', (tester) async {
    await tester.pumpWidget(const _Appli(depuisSonPropreContexte: false));
    await tester.pumpAndSettle();

    expect(tester.state<_AppliState>(find.byType(_Appli)).erreur, isNull);
    expect(find.text('Mise à jour requise'), findsOneWidget);
  });

  testWidgets('le contexte de l\'État qui construit MaterialApp ne le peut pas',
      (tester) async {
    // Contrepartie indispensable : sans elle, le test précédent passerait
    // encore si les deux contextes fonctionnaient, et ne prouverait donc pas
    // que le choix du contexte est ce qui décide.
    await tester.pumpWidget(const _Appli(depuisSonPropreContexte: true));
    await tester.pumpAndSettle();

    expect(tester.state<_AppliState>(find.byType(_Appli)).erreur, isNotNull,
        reason: 'showDialog doit lever depuis un contexte sans Navigator');
    expect(find.text('Mise à jour requise'), findsNothing);
  });

  test('check() ne reçoit plus de contexte, et main.dart ne lui en passe pas',
      () {
    // Le banc de widgets ci-dessus prouve la règle ; celui-ci prouve qu'elle
    // est appliquée là où le défaut se trouvait. Un contexte ne peut plus être
    // passé par erreur s'il n'y a plus de paramètre pour le recevoir.
    final service = File('lib/core/services/version_service.dart').readAsStringSync();
    final signature =
        RegExp(r'static Future<void> check\(([^)]*)\)').firstMatch(service);
    expect(signature, isNotNull, reason: 'signature de check() introuvable');
    expect(signature!.group(1), isNot(contains('BuildContext')),
        reason: 'check() ne doit pas recevoir de BuildContext : celui du seul '
                'appelant est au-dessus du MaterialApp');

    expect(service, contains('rootNavigatorKey'),
        reason: 'la fenêtre doit être ouverte depuis le navigateur racine');

    final main = File('lib/main.dart').readAsStringSync();
    final appel =
        RegExp(r'VersionService\.check\(([\s\S]*?)\);').firstMatch(main);
    expect(appel, isNotNull, reason: 'appel à VersionService.check introuvable');
    expect(appel!.group(1), isNot(contains('context')),
        reason: 'main.dart ne doit pas transmettre son contexte');
  });
}

/// La forme exacte de `main.dart` : un État dont le `build` retourne le
/// `MaterialApp`, et qui déclenche le contrôle depuis `initState`.
class _Appli extends StatefulWidget {
  final bool depuisSonPropreContexte;
  const _Appli({required this.depuisSonPropreContexte});

  @override
  State<_Appli> createState() => _AppliState();
}

class _AppliState extends State<_Appli> {
  /// Ce que le `catch (_)` de `check()` avalait.
  Object? erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = widget.depuisSonPropreContexte
          ? context
          : rootNavigatorKey.currentContext!;
      try {
        // Lien vide : `launchUrl` ne se termine jamais sans plateforme sous
        // `flutter test`. Le libellé du bouton ne dépend que de `lien != null`.
        await VersionService.afficherPourTest(ctx,
            message: 'Cette version n\'est plus prise en charge.',
            bloquant: true,
            lien: '');
      } catch (e) {
        erreur = e;
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: Text('accueil')),
      );
}
