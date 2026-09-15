import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/pages_legales.dart';

/// Ce qui se passe réellement quand on touche un lien légal.
///
/// ── Pourquoi un banc d'exécution et pas un contrôle de source ─────────────
///
/// `pages_legales_coherentes_test.dart` lit le fichier et vérifie qu'il
/// demande bien `LaunchMode.externalApplication`. C'est nécessaire et ça ne
/// suffit pas : la question n'est pas ce que le code demande, mais ce que
/// l'utilisateur obtient quand la demande échoue.
///
/// Or c'est exactement là qu'est le risque de cette bascule. Tant que les
/// pages s'ouvraient dans une webview interne, un échec avait un écran à lui,
/// avec son message. En passant au navigateur du système, l'échec n'a plus
/// rien : `launchUrl` peut lever, ou simplement renvoyer `false`, et dans les
/// deux cas le lien ne fait *rien*. Rien, c'est le défaut que ce projet a
/// déjà corrigé deux fois — et il ne se voit ni à la compilation, ni dans une
/// lecture du source.
///
/// Ce banc remplace donc le canal de `url_launcher` par un double, et regarde
/// l'écran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canalLanceur = MethodChannel('plugins.flutter.io/url_launcher');
  const url = 'https://pronowin.space/mentions-legales';

  late List<MethodCall> appels;
  late List<MethodCall> presses;

  /// Ce que le faux `url_launcher` répond à `launch`.
  late Object? Function() reponse;

  setUp(() {
    appels = [];
    presses = [];
    reponse = () => true;

    final messager =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messager.setMockMethodCallHandler(canalLanceur, (appel) async {
      appels.add(appel);
      if (appel.method == 'canLaunch') return true;
      if (appel.method == 'launch') {
        final r = reponse();
        if (r is Exception) throw r;
        return r;
      }
      return null;
    });

    // Le presse-papiers, pour l'action « Copier » du repli.
    messager.setMockMethodCallHandler(SystemChannels.platform, (appel) async {
      if (appel.method == 'Clipboard.setData') presses.add(appel);
      return null;
    });
  });

  tearDown(() {
    final messager =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messager.setMockMethodCallHandler(canalLanceur, null);
    messager.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Un écran réduit à un lien légal.
  Future<void> poser(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => PagesLegales.ouvrir(context, url,
                titre: 'Mentions légales'),
            child: const Text('Mentions légales'),
          ),
        ),
      ),
    ));
  }

  Future<void> toucher(WidgetTester tester) async {
    await tester.tap(find.text('Mentions légales'));
    await tester.pumpAndSettle();
  }

  MethodCall? lancement() =>
      appels.where((a) => a.method == 'launch').firstOrNull;

  group('quand un navigateur répond', () {
    testWidgets('la page part à l\'extérieur, pas dans l\'application',
        (tester) async {
      await poser(tester);
      await toucher(tester);

      final l = lancement();
      expect(l, isNotNull, reason: 'aucune ouverture demandée');
      expect(l!.arguments['url'], url);

      // `useWebView: false` est ce qui distingue `externalApplication` d'une
      // vue intégrée. C'est la demande de l'utilisateur, et le seul moyen de
      // la vérifier autrement qu'en relisant le source.
      expect(l.arguments['useWebView'], isFalse,
          reason: 'la page s\'ouvrirait encore dans l\'application');
    });

    testWidgets('et l\'écran ne se plaint de rien', (tester) async {
      await poser(tester);
      await toucher(tester);

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('quand aucun navigateur ne répond', () {
    testWidgets('un refus silencieux (`false`) est dit à l\'écran',
        (tester) async {
      // `launchUrl` ne lève pas toujours : il peut simplement renvoyer faux.
      // C'est le cas le plus traître, parce qu'il ne laisse aucune trace.
      reponse = () => false;

      await poser(tester);
      await toucher(tester);

      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'le lien n\'a rien fait et n\'a rien dit');
    });

    testWidgets('une erreur de la plateforme aussi', (tester) async {
      reponse = () => PlatformException(code: 'ACTIVITY_NOT_FOUND');

      await poser(tester);
      await toucher(tester);

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('l\'adresse reste lisible, donc atteignable', (tester) async {
      // Le texte légal doit rester joignable même quand l'ouverture échoue :
      // c'est ce qu'on garantit à l'utilisateur, pas le confort du lien.
      reponse = () => false;

      await poser(tester);
      await toucher(tester);

      expect(find.textContaining(url), findsOneWidget);
      expect(find.textContaining('Mentions légales'), findsWidgets,
          reason: 'le message doit nommer la page qu\'on n\'a pas pu ouvrir');
    });

    testWidgets('et elle se copie', (tester) async {
      reponse = () => false;

      await poser(tester);
      await toucher(tester);

      await tester.tap(find.text('Copier'));
      await tester.pumpAndSettle();

      expect(presses, hasLength(1));
      expect(presses.single.arguments['text'], url);
    });
  });
}
