import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/widgets/image_distante.dart';

/// Deux réglages invisibles qui décident du confort réel de l'application.
///
/// **Les images.** Dix-sept `Image.network` écrits à la main, aucun ne passant
/// `cacheWidth` : Flutter décodait chaque fichier à sa résolution d'origine —
/// un écusson de 512 px pour une case de 16, une photo de joueur de 500 px pour
/// un rond de 26. Un classement en affiche vingt, une composition vingt-deux.
/// Aucun ne mettait en cache sur disque non plus : revenir sur un écran
/// retéléchargeait tout, ce qui se paie en données mobiles.
///
/// **L'échelle de texte.** `TextScaler.noScaling` annulait purement et
/// simplement le réglage système. Qui a agrandi le texte de son téléphone parce
/// qu'il lit mal retrouvait ici les tailles d'origine, sans recours.
void main() {
  Iterable<File> sources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  /// Le contenu d'un fichier, commentaires retirés.
  ///
  /// Sans cela, un contrôle se satisfait de la phrase qui explique la
  /// correction : retirer `memCacheWidth` du code laissait le test vert parce
  /// que le commentaire juste au-dessus en parle. Un contrôle qui se valide
  /// sur sa propre prose ne garde rien.
  String codeSeul(String chemin) => File(chemin)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  group('images distantes', () {
    test('aucune n\'est chargée sans passer par un widget dimensionné', () {
      // La règle porte sur l'appel brut : `Image.network` ne sait pas à quelle
      // taille il sera peint, donc décode en grand. Deux widgets savent —
      // `ImageDistante` et `TeamLogoWidget` — et eux seuls ont le droit.
      final fautifs = <String>[];

      for (final f in sources()) {
        final nom = f.uri.pathSegments.last;
        if (nom == 'image_distante.dart' || nom == 'team_logo_widget.dart') continue;

        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (lignes[i].trimLeft().startsWith('//')) continue;
          if (lignes[i].contains('Image.network')) {
            fautifs.add('${f.path.replaceAll(r'\', '/')}:${i + 1}');
          }
        }
      }

      expect(fautifs, isEmpty,
        reason: 'passer par ImageDistante :\n${fautifs.join('\n')}');
    });

    test('l\'analyseur a bien parcouru le projet', () {
      // Sans ce contrôle, un parcours qui ne trouve aucun fichier rendrait le
      // test précédent vert par vacuité.
      final tout = sources().toList();
      expect(tout.length, greaterThanOrEqualTo(80));
      expect(tout.any((f) => f.uri.pathSegments.last == 'main.dart'), isTrue);
    });

    test('la taille de décodage suit la densité de l\'écran', () {
      final src = codeSeul('lib/core/widgets/image_distante.dart');

      expect(src, contains('memCacheWidth:'));
      expect(src, contains('memCacheHeight:'));
      // Un facteur fixe flouterait sur un écran 3× et gaspillerait sur un 1,5×.
      expect(src, contains('devicePixelRatioOf'));
      // Faute de taille explicite, on lit les contraintes plutôt que d'abandonner.
      expect(src, contains('hasBoundedWidth'));
    });

    test('les écussons sont décodés à leur taille eux aussi', () {
      final src = codeSeul('lib/core/widgets/team_logo_widget.dart');

      expect(src, contains('memCacheWidth:'));
      expect(src, contains('memCacheHeight:'));
      expect(src, contains('devicePixelRatioOf'));
    });
  });

  group('ImageDistante se rend là où on l\'a posée', () {
    // Le widget lit désormais les contraintes de mise en page. Un contrôle de
    // forme ne dirait rien d'une assertion de layout : ces cas se rendent pour
    // de vrai, dans les trois situations où les points d'appel le placent.
    const repli = Icon(Icons.person_rounded, size: 15);

    Future<void> rendre(WidgetTester tester, Widget enfant) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: enfant)));

    testWidgets('adresse vide : le repli, sans requête', (tester) async {
      await rendre(tester, const ImageDistante(url: '', repli: repli));

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('adresse nulle : le repli aussi', (tester) async {
      await rendre(tester, const ImageDistante(url: null, repli: repli));

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('taille explicite : elle est respectée', (tester) async {
      await rendre(tester, const Center(
        child: ImageDistante(
          url: '', repli: repli, largeur: 26, hauteur: 26)));

      expect(tester.takeException(), isNull);
    });

    testWidgets('contraintes bornées : aucune assertion', (tester) async {
      await rendre(tester, const SizedBox(
        width: 120, height: 80,
        child: ImageDistante(url: '', repli: repli)));

      expect(tester.takeException(), isNull);
    });

    testWidgets('largeur non bornée : aucune assertion non plus', (tester) async {
      // Le cas qui casse : une Row donne une largeur infinie à ses enfants
      // non contraints. Le widget doit s'en accommoder au lieu de lever.
      await rendre(tester, const Row(children: [
        ImageDistante(url: '', repli: repli, largeur: 20, hauteur: 20),
      ]));

      expect(tester.takeException(), isNull);
    });
  });

  group('échelle de texte', () {
    // Les commentaires citent volontairement le défaut corrigé : les inclure
    // rendrait le contrôle rouge pour la phrase qui explique la correction.
    final main = codeSeul('lib/main.dart');

    test('le réglage système n\'est plus annulé', () {
      expect(main.contains('TextScaler.noScaling'), isFalse,
        reason: 'ignorer le réglage prive de l\'application ceux qui en ont '
                'le plus besoin');
    });

    test('il est borné, et la borne laisse passer les réglages courants', () {
      final m = RegExp(r'maxScaleFactor:\s*([\d.]+)').firstMatch(main);
      expect(m, isNotNull, reason: 'aucune borne haute déclarée');

      final max = double.parse(m!.group(1)!);
      // Assez pour couvrir les réglages « Grand » des deux systèmes…
      expect(max, greaterThanOrEqualTo(1.3));
      // …sans faire déborder les cartes à hauteur fixe, où la promesse serait
      // tenue par un texte tronqué.
      expect(max, lessThanOrEqualTo(1.6));
    });
  });
}
