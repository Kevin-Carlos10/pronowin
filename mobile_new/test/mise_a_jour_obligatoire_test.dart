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

  // ── Quand la fenêtre doit-elle bloquer ──────────────────────────────────
  //
  // `APK_FORCE_UPDATE` bloquait seul, sans regarder la version installée.
  // Activé alors que tout le monde était déjà à jour, il enfermait l'ensemble
  // des utilisateurs derrière une fenêtre sans issue, dont l'unique bouton
  // retéléchargeait la version déjà installée. Relancer n'y changeait rien :
  // la condition ne dépendait pas de ce qui était installé, donc aucune
  // installation ne pouvait la lever.
  //
  // C'est le même piège que `MIN > LATEST`, arrivé par l'autre porte. Le
  // contrôle serveur ne pouvait pas l'attraper : un booléen n'a rien à
  // contredire.
  group('décision de blocage', () {
    ({bool obligatoire, bool disponible}) d({
      required String courante,
      String min    = '1.0.0',
      String latest = '1.0.0',
      bool force    = false,
    }) => VersionService.decider(
        courante: courante, min: min, latest: latest, force: force);

    test('en dessous du minimum : bloquant', () {
      expect(d(courante: '1.0.4', min: '1.0.9', latest: '1.0.9').obligatoire,
          isTrue);
    });

    test('au-dessus du minimum mais pas à jour : proposé, pas imposé', () {
      final r = d(courante: '1.0.5', min: '1.0.0', latest: '1.0.9');
      expect(r.obligatoire, isFalse);
      expect(r.disponible,  isTrue);
    });

    test('déjà à jour : rien du tout', () {
      final r = d(courante: '1.0.9', min: '1.0.9', latest: '1.0.9');
      expect(r.obligatoire, isFalse);
      expect(r.disponible,  isFalse);
    });

    test('force ne bloque pas un utilisateur déjà à jour', () {
      // Le défaut : la fenêtre s'ouvrait, ne se fermait pas, et proposait de
      // télécharger la version déjà installée.
      expect(d(courante: '1.0.9', min: '1.0.0', latest: '1.0.9', force: true)
          .obligatoire, isFalse);
    });

    test('force bloque quand une version existe vraiment', () {
      // Contrepartie : sans ce point, neutraliser `force` entièrement
      // passerait le test précédent.
      expect(d(courante: '1.0.4', min: '1.0.0', latest: '1.0.9', force: true)
          .obligatoire, isTrue);
    });

    test('les nombres, pas les chaînes', () {
      // « 1.10.0 » est postérieur à « 1.9.0 » ; l'ordre lexicographique dit
      // l'inverse et laisserait passer une version périmée.
      expect(d(courante: '1.9.0', min: '1.10.0', latest: '1.10.0').obligatoire,
          isTrue);
    });

    test('le numéro de build ne participe pas au classement', () {
      expect(d(courante: '1.0.9+42', min: '1.0.9', latest: '1.0.9').obligatoire,
          isFalse);
    });
  });
}
