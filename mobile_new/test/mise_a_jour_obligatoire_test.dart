import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/installateur_maj.dart';
import 'package:pronowin/core/services/version_service.dart';
import 'package:pronowin/core/widgets/ecran_mise_a_jour.dart';

/// Une mise à jour obligatoire ne se quitte sur aucun geste.
///
/// L'APK distribué hors store ne se met jamais à jour tout seul : quand une
/// version devient obligatoire, la seule chose qui protège l'utilisateur d'une
/// version périmée est cet écran.
///
/// Il verrouillait bien la barrière et le bouton retour — mais son unique
/// bouton, « Mettre à jour », lançait le téléchargement puis **fermait la
/// fenêtre**. L'utilisateur revenait du navigateur dans une application
/// débloquée, sur la version qu'on venait de déclarer trop ancienne. Le blocage
/// tenait à tout sauf à la seule action qu'il proposait.
///
/// ── Ce n'est plus une fenêtre ─────────────────────────────────────────────
///
/// L'`AlertDialog` est devenue un écran plein qui télécharge lui-même et montre
/// son avancement. L'écart que le blocage devait couvrir était le plus long du
/// parcours : soixante-dix mégaoctets, puis une installation, pendant lesquels
/// l'utilisateur ne savait pas où il en était — et pendant lesquels
/// l'application restait derrière, utilisable.
///
/// Les garanties ne changent pas de nature : obligatoire, rien ne ferme ;
/// facultative, tout ferme. S'y ajoute le téléchargement, qui verrouille aussi
/// le retour — l'interrompre laisserait un fichier tronqué et une application
/// qu'on vient de déclarer périmée.
void main() {
  /// Monte un écran d'où l'on peut ouvrir celui de mise à jour.
  ///
  /// Le téléchargement et l'installation sont injectés : sans plateforme, ni le
  /// réseau ni l'installateur ne répondent sous `flutter test`, et l'écran
  /// resterait figé sur son premier état sans qu'aucune assertion ne le dise.
  Future<void> ouvrir(
    WidgetTester tester, {
    required bool bloquant,
    String lien = '',
    bool installationDirecte = false,
    Future<File> Function(
      String, {
      required void Function(double) progression,
      CancelToken? annulation,
    })? telechargeur,
    Future<ResultatInstallation> Function(File)? installeur,
    Future<bool> Function(Uri)? ouvreur,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<ReponseMaj>(
                  builder: (_) => EcranMiseAJour(
                    message: 'Une nouvelle version est disponible.',
                    bloquant: bloquant,
                    lien: lien,
                    installationDirecte: installationDirecte,
                    telechargeur: telechargeur,
                    installeur: installeur,
                    ouvreur: ouvreur,
                  ),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  final action = find.byKey(const Key('maj-action'));
  final titre  = find.byKey(const Key('maj-titre'));

  String texteDe(WidgetTester tester, Finder f) =>
      (tester.widget(f) as Text).data!;

  /// Le libellé du bouton d'action.
  ///
  /// La clé est posée sur le bouton, pas sur son `Text` : c'est le bouton que
  /// les tests touchent, et une clé sur le libellé ne permettrait pas de le
  /// viser.
  String libelleAction(WidgetTester tester) => tester
      .widget<Text>(find.descendant(
        of: find.byKey(const Key('maj-action')),
        matching: find.byType(Text)))
      .data!;

  // ── Verrouillage ────────────────────────────────────────────────────────

  testWidgets('obligatoire : aucune échappatoire proposée', (tester) async {
    await ouvrir(tester, bloquant: true);

    expect(texteDe(tester, titre), 'Mise à jour requise');
    expect(find.byKey(const Key('maj-plus-tard')), findsNothing,
        reason: 'un « Plus tard » sur une mise à jour obligatoire la rend '
                'facultative');
  });

  testWidgets('obligatoire : le bouton retour ne referme pas', (tester) async {
    await ouvrir(tester, bloquant: true);

    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();

    expect(titre, findsOneWidget, reason: 'PopScope ne retient plus l\'écran');
  });

  testWidgets('facultative : « Plus tard » referme', (tester) async {
    // Contrepartie : un écran qui ne se fermerait jamais passerait les deux
    // tests précédents, et rendrait toute mise à jour facultative bloquante —
    // le défaut symétrique, et tout aussi grave.
    await ouvrir(tester, bloquant: false);
    expect(texteDe(tester, titre), 'Mise à jour disponible');

    await tester.tap(find.byKey(const Key('maj-plus-tard')));
    await tester.pumpAndSettle();
    expect(titre, findsNothing);
  });

  testWidgets('facultative : le retour referme aussi', (tester) async {
    await ouvrir(tester, bloquant: false);

    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();

    expect(titre, findsNothing);
  });

  // ── Canal store : la boutique, rien d'autre ─────────────────────────────

  testWidgets('canal store : le bouton ouvre la fiche, sans rien télécharger',
      (tester) async {
    // Installer un APK hors Play est réservé aux boutiques d'applications. La
    // variante des boutiques ne déclare même pas la permission : si cet écran
    // y tentait un téléchargement, il s'arrêterait sur une erreur au moment de
    // l'installation, après soixante-dix mégaoctets.
    Uri? demandee;
    var telechargements = 0;

    await ouvrir(tester,
      bloquant: true,
      lien: 'https://play.google.com/store/apps/details?id=com.pronowin.app',
      installationDirecte: false,
      ouvreur: (u) async { demandee = u; return true; },
      telechargeur: (url, {required progression, annulation}) async {
        telechargements++;
        return File('jamais');
      });

    expect(libelleAction(tester), 'Mettre à jour');
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(demandee.toString(), contains('play.google.com'));
    expect(telechargements, 0,
        reason: 'le canal store ne doit rien télécharger lui-même');
  });

  // ── Canal direct : téléchargement et installation ───────────────────────

  testWidgets('direct : la progression affichée est celle du téléchargement',
      (tester) async {
    final fin = Completer<File>();

    await ouvrir(tester,
      bloquant: true,
      lien: 'https://pronowin.space/downloads/app-release.apk',
      installationDirecte: true,
      telechargeur: (url, {required progression, annulation}) {
        progression(0.42);
        return fin.future;
      },
      installeur: (f) async => ResultatInstallation.ouvert);

    expect(libelleAction(tester), 'Installer');
    await tester.tap(action);
    await tester.pump();

    expect(texteDe(tester, titre), 'Appli en cours de mise à jour');
    expect(find.text('42 %'), findsOneWidget);
    expect(find.text('L\'installation peut durer quelques minutes.'),
        findsOneWidget);

    // Pendant le téléchargement, le retour est refusé lui aussi : l'interrompre
    // laisserait un fichier tronqué et une application déclarée périmée.
    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pump();
    expect(titre, findsOneWidget);

    fin.complete(File('essai.apk'));
    await tester.pumpAndSettle();
    expect(texteDe(tester, titre), 'Installation en cours',
        reason: 'l\'installateur a la main, l\'écran doit le dire');
  });

  testWidgets('direct : sans taille annoncée, aucun pourcentage inventé',
      (tester) async {
    // `onReceiveProgress` rend -1 quand le serveur n'annonce pas de taille.
    // Afficher « 0 % » qui n'avance jamais serait pire que de ne rien promettre.
    final fin = Completer<File>();

    await ouvrir(tester,
      bloquant: true,
      lien: 'https://pronowin.space/downloads/app-release.apk',
      installationDirecte: true,
      telechargeur: (url, {required progression, annulation}) => fin.future);

    await tester.tap(action);
    await tester.pump();

    expect(find.text('Préparation…'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    // Pas de `pumpAndSettle` ici : une barre indéterminée tourne sans fin, et
    // l'attente ne rendrait jamais la main. C'est la contrepartie de ce que le
    // test vérifie.
    fin.complete(File('essai.apk'));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('direct : un téléchargement qui échoue le dit et propose de recommencer',
      (tester) async {
    await ouvrir(tester,
      bloquant: true,
      lien: 'https://pronowin.space/downloads/app-release.apk',
      installationDirecte: true,
      telechargeur: (url, {required progression, annulation}) =>
          Future<File>.error(DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.connectionError,
          )));

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(texteDe(tester, titre), 'La mise à jour a échoué');
    expect(find.textContaining('connexion'), findsOneWidget);
    expect(libelleAction(tester), 'Réessayer',
        reason: 'un écran bloquant qui échoue sans permettre de recommencer '
                'enferme l\'utilisateur pour de bon');
  });

  testWidgets('direct : l\'autorisation manquante est expliquée', (tester) async {
    // Depuis Android 8, l'autorisation d'installer se donne application par
    // application. Sans elle, l'installateur ne s'ouvre pas — et rien, à
    // l'écran, ne disait pourquoi.
    await ouvrir(tester,
      bloquant: true,
      lien: 'https://pronowin.space/downloads/app-release.apk',
      installationDirecte: true,
      telechargeur: (url, {required progression, annulation}) async =>
          File('essai.apk'),
      installeur: (f) async => ResultatInstallation.autorisationDemandee);

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.textContaining('Autorisez PronoWin'), findsOneWidget);
    expect(libelleAction(tester), 'Réessayer');
  });

  testWidgets('direct : l\'autorisation accordée ne fait pas retélécharger',
      (tester) async {
    // Le parcours observé sur appareil : l'installation échoue faute
    // d'autorisation, l'utilisateur la donne, revient, appuie sur
    // « Réessayer » — et la première version repartait de zéro pour
    // soixante-dix mégaoctets déjà sur le disque. Sur un forfait mobile, c'est
    // payer deux fois la même chose pour une case à cocher.
    final fichier = File('${Directory.systemTemp.path}/pronowin-essai.apk')
      ..writeAsStringSync('artefact');
    addTearDown(() {
      if (fichier.existsSync()) fichier.deleteSync();
    });

    var telechargements = 0;
    var installations = 0;

    await ouvrir(tester,
      bloquant: true,
      lien: 'https://pronowin.space/downloads/app-release.apk',
      installationDirecte: true,
      telechargeur: (url, {required progression, annulation}) async {
        telechargements++;
        return fichier;
      },
      installeur: (f) async {
        installations++;
        return installations == 1
            ? ResultatInstallation.autorisationDemandee
            : ResultatInstallation.ouvert;
      });

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(telechargements, 1);
    expect(libelleAction(tester), 'Réessayer');

    await tester.tap(action);
    // Pas de `pumpAndSettle` : l'étape d'installation affiche une barre
    // indéterminée, qui tourne sans fin et ne rendrait jamais la main.
    await tester.pump();
    await tester.pump();

    expect(telechargements, 1,
        reason: 'le fichier est déjà complet sur le disque : le retélécharger '
                'fait payer deux fois soixante-dix mégaoctets');
    expect(installations, 2,
        reason: 'le réessai doit bien relancer l\'installation');
    expect(texteDe(tester, titre), 'Installation en cours');
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
