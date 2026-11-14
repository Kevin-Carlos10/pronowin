import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/widgets/pile_onglets_paresseuse.dart';

/// Un onglet jamais ouvert ne doit rien construire — et un onglet déjà ouvert
/// ne doit rien reperdre.
///
/// Les deux moitiés comptent autant l'une que l'autre. Différer la première
/// construction sans conserver l'état ensuite donnerait une application qui
/// recharge tout à chaque aller-retour entre deux onglets : on aurait déplacé
/// le coût du démarrage vers la navigation, pas supprimé.

/// Un onglet qui dit combien de fois il a été créé, et qui retient un compteur
/// que seul un remplacement d'état peut remettre à zéro.
class _Onglet extends StatefulWidget {
  final String nom;
  final Map<String, int> creations;
  const _Onglet(this.nom, this.creations);

  @override
  State<_Onglet> createState() => _OngletState();
}

class _OngletState extends State<_Onglet> {
  int compteur = 0;

  @override
  void initState() {
    super.initState();
    widget.creations[widget.nom] = (widget.creations[widget.nom] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('${widget.nom}:$compteur'),
      TextButton(
        onPressed: () => setState(() => compteur++),
        child: Text('inc-${widget.nom}'),
      ),
      Text('${widget.nom}-visible:${OngletVisible.de(context)}'),
    ]);
  }
}

/// Un hôte minimal qui reproduit ce que fait la barre de navigation.
class _Hote extends StatefulWidget {
  final Map<String, int> creations;
  const _Hote(this.creations);

  @override
  State<_Hote> createState() => _HoteState();
}

class _HoteState extends State<_Hote> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: PileOngletsParesseuse(
          index: index,
          children: [
            _Onglet('a', widget.creations),
            _Onglet('b', widget.creations),
            _Onglet('c', widget.creations),
          ],
        ),
        bottomNavigationBar: Row(
          children: [
            for (var i = 0; i < 3; i++)
              TextButton(
                onPressed: () => setState(() => index = i),
                child: Text('vers-$i'),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late Map<String, int> creations;

  setUp(() => creations = <String, int>{});

  Future<void> monter(WidgetTester t) async {
    await t.pumpWidget(_Hote(creations));
    await t.pump();
  }

  group('rien ne se construit avant d etre ouvert', () {
    testWidgets('au demarrage, seul le premier onglet existe', (t) async {
      await monter(t);

      expect(creations['a'], 1, reason: "l'onglet affiche doit etre construit");
      expect(creations['b'], isNull,
          reason: 'un onglet jamais ouvert ne doit lire aucun provider, '
              'donc ne declencher aucune requete');
      expect(creations['c'], isNull);
    });

    testWidgets('ouvrir un onglet le construit, une seule fois', (t) async {
      await monter(t);

      await t.tap(find.text('vers-1'));
      await t.pumpAndSettle();
      expect(creations['b'], 1);
      expect(creations['c'], isNull, reason: 'le troisieme reste inexplore');

      await t.tap(find.text('vers-0'));
      await t.pumpAndSettle();
      await t.tap(find.text('vers-1'));
      await t.pumpAndSettle();
      expect(creations['b'], 1,
          reason: 'revenir sur un onglet deja vu ne doit pas le reconstruire');
    });
  });

  group('ce qui a ete ouvert reste vivant', () {
    testWidgets('l etat survit a un aller-retour', (t) async {
      await monter(t);

      await t.tap(find.text('inc-a'));
      await t.pumpAndSettle();
      expect(find.text('a:1'), findsOneWidget);

      await t.tap(find.text('vers-2'));
      await t.pumpAndSettle();
      await t.tap(find.text('vers-0'));
      await t.pumpAndSettle();

      expect(find.text('a:1'), findsOneWidget,
          reason: "c'est ce qu'apportait IndexedStack : le defilement, les "
              'filtres et les compteurs ne repartent pas de zero');
      expect(creations['a'], 1);
    });
  });

  group('chaque onglet sait s il est regarde', () {
    testWidgets('un seul se declare visible a la fois', (t) async {
      await monter(t);
      await t.tap(find.text('vers-1'));
      await t.pumpAndSettle();

      // Les deux sont construits ; un seul est regarde. `skipOffstage: false`
      // est indispensable : IndexedStack place les onglets caches hors-scene,
      // et un chercheur qui les saute ne verrait jamais leur reponse — le banc
      // passerait alors sans rien avoir verifie.
      expect(find.text('a-visible:false', skipOffstage: false), findsOneWidget);
      expect(find.text('b-visible:true'), findsOneWidget);
    });

    testWidgets('la reponse suit le changement d onglet', (t) async {
      await monter(t);
      expect(find.text('a-visible:true'), findsOneWidget);

      await t.tap(find.text('vers-1'));
      await t.pumpAndSettle();
      expect(find.text('a-visible:false', skipOffstage: false), findsOneWidget,
          reason: "sans dependance a l'InheritedWidget, la page resterait sur "
              'sa derniere reponse et son minuteur continuerait');
    });

    testWidgets('hors d une pile, une page se considere visible', (t) async {
      // Une page ouverte seule, ou montee dans un banc : rien ne doit
      // dependre de la presence de la pile.
      await t.pumpWidget(MaterialApp(home: _Onglet('seul', creations)));
      await t.pump();
      expect(find.text('seul-visible:true'), findsOneWidget);
    });
  });
}
