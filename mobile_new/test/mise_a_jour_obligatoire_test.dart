import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/version_service.dart';

/// Une mise à jour obligatoire ne se referme sur aucun geste.
///
/// L'APK distribué hors store ne se met jamais à jour tout seul : quand une
/// version devient obligatoire, la seule chose qui protège l'utilisateur d'une
/// version périmée est cette fenêtre.
///
/// Elle verrouillait bien la barrière (`barrierDismissible: false`) et le
/// bouton retour (`PopScope(canPop: false)`) — mais son unique bouton,
/// « Mettre à jour », lançait le téléchargement puis **fermait la fenêtre**.
/// L'utilisateur revenait du navigateur dans une application débloquée, sur la
/// version qu'on venait de déclarer trop ancienne. Le blocage tenait à tout
/// sauf à la seule action qu'il proposait.
///
/// Sur le canal direct, l'écart est le plus long : télécharger soixante-dix
/// mégaoctets puis installer prend plusieurs minutes.
///
/// ── Pourquoi le lien est vide dans ces tests ──────────────────────────────
///
/// `launchUrl` ne se termine jamais sans plateforme : le canal natif n'est pas
/// enregistré sous `flutter test`, et l'`await` reste suspendu — la suite du
/// gestionnaire n'est donc jamais atteinte. Un lien vide court-circuite le
/// lancement (`lien.isNotEmpty` est faux) sans changer le libellé du bouton,
/// qui ne dépend que de `lien != null`. On éprouve donc exactement la décision
/// de fermeture, sans dépendre d'un greffon qu'un test ne peut pas fournir.
void main() {
  /// Monte un écran d'où l'on peut ouvrir la fenêtre.
  Future<void> ouvrir(
    WidgetTester tester, {
    required bool bloquant,
    String lien = '',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: TextButton(
          onPressed: () => VersionService.afficherPourTest(
            context,
            message:  'Une nouvelle version est disponible.',
            bloquant: bloquant,
            lien:     lien),
          child: const Text('ouvrir'))))),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('obligatoire : le bouton ne referme pas la fenêtre', (tester) async {
    await ouvrir(tester, bloquant: true);

    expect(find.text('Mise à jour requise'), findsOneWidget);
    // Aucune échappatoire proposée.
    expect(find.text('Plus tard'), findsNothing);

    await tester.tap(find.text('Mettre à jour'));
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour requise'), findsOneWidget,
      reason: 'la fenêtre s\'est refermée : l\'utilisateur retrouve une '
              'application utilisable sur la version qu\'on vient de refuser');
  });

  testWidgets('obligatoire : le bouton retour ne la referme pas non plus', (tester) async {
    await ouvrir(tester, bloquant: true);

    // Le geste « retour » d'Android, celui qui ferme une boîte ordinaire.
    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour requise'), findsOneWidget,
      reason: 'PopScope ne retient plus la fenêtre');
  });

  testWidgets('facultative : les deux boutons la referment', (tester) async {
    // Sans ce point, une fenêtre qui ne se fermerait jamais passerait les deux
    // tests précédents — et rendrait toute mise à jour facultative bloquante,
    // ce qui est le défaut symétrique et tout aussi grave.
    await ouvrir(tester, bloquant: false);
    expect(find.text('Mise à jour disponible'), findsOneWidget);

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(find.text('Mise à jour disponible'), findsNothing,
      reason: '« Plus tard » doit refermer la fenêtre');

    await ouvrir(tester, bloquant: false);
    await tester.tap(find.text('Mettre à jour'));
    await tester.pumpAndSettle();
    expect(find.text('Mise à jour disponible'), findsNothing,
      reason: 'sur une mise à jour facultative, « Mettre à jour » referme aussi');
  });

  testWidgets('facultative : la barrière et le retour la referment', (tester) async {
    await ouvrir(tester, bloquant: false);

    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour disponible'), findsNothing,
      reason: 'une mise à jour facultative doit rester refermable au retour');
  });
}
