import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/widgets/bottom_nav_metrics.dart';

/// `MainScaffold` déclare `extendBody: true` : le contenu passe derrière la
/// barre de navigation. Chaque page défilante doit donc réserver au moins
/// l'empreinte de cette barre, sinon sa dernière ligne est masquée.
///
/// La page Compte réservait 80 px écrits à la main, pour une empreinte allant
/// jusqu'à 102 px sur un iPhone à barre d'accueil : 22 px de contenu passaient
/// sous la barre.
void main() {
  _barreStable();
  /// Hauteur de la barre et place réservée, mesurées dans le même contexte.
  ///
  /// La hauteur n'est plus une constante : elle suit l'échelle de texte de
  /// l'appareil, sans quoi un libellé agrandi déborderait d'une barre figée.
  /// Le mesurer plutôt que l'écrire ici évite d'en recopier la valeur — c'est
  /// exactement la duplication que ce fichier existe pour empêcher.
  Future<({double hauteur, double espace})> mesurer(
    WidgetTester tester, {
    double insetBas = 0,
    double echelleTexte = 1,
    double supplement = 16,
  }) async {
    late double hauteur;
    late double espace;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(
        padding: EdgeInsets.only(bottom: insetBas),
        textScaler: TextScaler.linear(echelleTexte),
      ),
      child: Builder(builder: (context) {
        hauteur = BottomNavMetrics.hauteur(context);
        espace  = bottomNavSpace(context, supplement: supplement);
        return const SizedBox.shrink();
      }),
    ));
    return (hauteur: hauteur, espace: espace);
  }

  group('bottomNavSpace couvre la barre sur tous les appareils', () {
    // iPhone à barre d'accueil : 34. Android gestuel : ~24. Boutons : 0.
    for (final inset in [0.0, 24.0, 34.0, 48.0]) {
      testWidgets('encoche de $inset px', (tester) async {
        final m = await mesurer(tester, insetBas: inset);
        expect(m.espace,
            greaterThanOrEqualTo(m.hauteur + BottomNavMetrics.margeBasse + inset),
            reason: 'la dernière ligne passerait sous la barre');
      });
    }

    testWidgets('l\'ancienne valeur écrite à la main était bien trop courte',
        (tester) async {
      // Le test qui aurait attrapé le défaut : 80 px ne suffisent pas dès que
      // l'encoche dépasse 12 px, ce qui est le cas de tout appareil récent.
      const ancienneValeur = 80.0;
      final iphone  = await mesurer(tester, insetBas: 34);
      final android = await mesurer(tester, insetBas: 24);

      expect(ancienneValeur,
          lessThan(iphone.hauteur + BottomNavMetrics.margeBasse + 34),
          reason: 'sur iPhone, 80 px laissaient 22 px de contenu masqués');
      expect(ancienneValeur,
          lessThan(android.hauteur + BottomNavMetrics.margeBasse + 24),
          reason: 'en navigation gestuelle Android aussi');

      // Et la valeur dérivée, elle, tient.
      expect(iphone.espace, greaterThan(ancienneValeur));
    });

    testWidgets('le supplément de respiration est réglable', (tester) async {
      final m = await mesurer(tester, supplement: 0);
      expect(m.espace, m.hauteur + BottomNavMetrics.margeBasse);
    });
  });

  group("la barre suit l'échelle de texte du téléphone", () {
    // La hauteur valait 64 en dur. Quelqu'un ayant agrandi les caractères de
    // son système voyait le libellé grandir dans une barre qui, elle, ne
    // bougeait pas — jusqu'au débordement.
    testWidgets('elle grandit avec les caractères', (tester) async {
      final normal = await mesurer(tester);
      final grand  = await mesurer(tester, echelleTexte: 1.5);

      expect(grand.hauteur, greaterThan(normal.hauteur),
          reason: "le libellé agrandi déborderait d'une barre figée");
    });

    testWidgets('et la place réservée suit toute seule', (tester) async {
      // Le couplage qui compte : une barre plus haute sans réservation plus
      // grande masquerait la dernière ligne de chaque liste — le défaut même
      // que ce fichier a été écrit pour empêcher.
      final normal = await mesurer(tester, insetBas: 34);
      final grand  = await mesurer(tester, insetBas: 34, echelleTexte: 1.5);

      expect(grand.espace, greaterThan(normal.espace));
      expect(grand.espace,
          greaterThanOrEqualTo(grand.hauteur + BottomNavMetrics.margeBasse + 34));
    });

    testWidgets("à l'échelle normale, rien ne change", (tester) async {
      // Le contre-test : faire grandir la barre sans raison volerait de la
      // place au contenu sur tous les appareils.
      final m = await mesurer(tester);
      expect(m.hauteur, 64);
    });
  });
}

/// La barre ne se réduit plus au défilement.
///
/// ── Ce qu'elle faisait ────────────────────────────────────────────────────
///
/// Un `NotificationListener` surveillait le sens du défilement et faisait
/// tomber la barre entière à **82 %** vers le bas. Le libellé, déjà à 10 px,
/// se lisait alors autour de 8 ; la surface touchable perdait près d'un
/// cinquième — au moment précis où l'on parcourt une liste, et donc où l'on
/// peut vouloir changer d'onglet.
///
/// Le gain annoncé était « plus de place pour le contenu » : une dizaine de
/// pixels. Un élément de navigation est soit pleinement utilisable, soit
/// absent ; entre les deux, il occupe la place sans se laisser atteindre.
///
/// ── Pourquoi ce contrôle lit la source ────────────────────────────────────
///
/// Les mesures ci-dessus portent sur `BottomNavMetrics`, pas sur ce que la
/// barre peint. Remettre un facteur d'échelle à l'affichage les laisserait
/// toutes vertes — vérifié par injection.
///
/// Monter `MainScaffold` demanderait routeur et fournisseurs d'authentification
/// pour un seul attribut visuel. Le mécanisme ayant été **retiré** et non
/// débranché, contrôler son absence suffit : il n'y a plus de champ à relire,
/// plus d'écouteur à rebrancher.
void _barreStable() {
  final source =
      File('lib/shared/widgets/main_scaffold.dart').readAsStringSync();

  group('la barre de navigation garde sa taille', () {
    test('aucun facteur d\'échelle ne lui est appliqué', () {
      expect(source, isNot(contains('AnimatedScale')),
          reason: 'une barre à 82 % rend ses libellés illisibles et ses '
              'cibles trop petites');
      expect(source, isNot(contains('0.82')));
    });

    test('et plus rien n\'écoute le défilement pour la redimensionner', () {
      // Retiré plutôt que débranché : un écouteur qui n'alimente qu'un champ
      // que personne ne lit se remet en service tout seul le jour où
      // quelqu'un le croit encore utile.
      expect(source, isNot(contains('UserScrollNotification')));
      expect(source, isNot(contains('_navVisible')));
    });

    test('le libellé vient de la métrique partagée', () {
      // Écrit en dur, il divergerait de la hauteur calculée à partir de lui.
      expect(source, contains('BottomNavMetrics.taillePolice'));
      expect(BottomNavMetrics.taillePolice, greaterThan(10));
    });
  });
}
