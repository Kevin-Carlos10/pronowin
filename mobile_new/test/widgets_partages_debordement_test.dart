import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/shared/widgets/confidence_indicator.dart';
import 'package:pronowin/shared/widgets/erreur_chargement.dart';
import 'package:pronowin/shared/widgets/guest_locked_view.dart';
import 'package:pronowin/shared/widgets/pw_button.dart';

/// Le harnais de débordement, étendu aux widgets réutilisés partout.
///
/// La carte de match a le sien : c'est le widget le plus affiché, et trois
/// débordements y ont été trouvés. Mais un défaut dans un widget *partagé*
/// coûte plus cher encore — il apparaît sur chaque écran qui l'emploie, et se
/// corrige une seule fois.
///
/// Ces quatre-là portent du texte, se construisent sans fournisseur, et sont
/// employés d'un bout à l'autre de l'application : le bouton principal, l'état
/// d'erreur, le verrou invité, la jauge de confiance.
///
/// Le texte français est volontairement long. « Réessayer » tient partout ;
/// « Créer un compte gratuit pour continuer » est la vraie longueur des
/// libellés de l'application, et c'est elle qui révèle les rangées trop
/// serrées.
void main() {
  /// Rend [enfant] à l'échelle et à la largeur demandées.
  ///
  /// [page] distingue deux natures. Un widget-carte est posé dans un `Scaffold`
  /// et une zone défilante, comme dans une liste. Un widget-page porte déjà son
  /// propre `Scaffold` : l'enfermer dans une zone défilante lui donnerait une
  /// hauteur infinie, et l'assertion de mise en page qui s'ensuit se lirait
  /// comme un débordement de l'application. Elle ne viendrait que du harnais —
  /// c'est arrivé, et j'ai failli corriger un widget sain.
  Future<void> rendre(
    WidgetTester tester,
    Widget enfant, {
    required double echelle,
    required double largeur,
    bool page = false,
  }) async {
    tester.view.physicalSize = Size(largeur, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(echelle)),
            child: page
                ? enfant
                : Scaffold(body: SingleChildScrollView(child: enfant)),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Les mêmes bornes que la carte de match : c'est `maxScaleFactor` qui les
  /// fixe, et un widget partagé n'a pas le droit d'être le maillon faible.
  const echelles = [1.0, 1.3, 1.5];
  const largeurs = [320.0, 360.0, 411.0];

  /// Déclare la même batterie pour un widget donné.
  void batterie(String nom, Widget Function() fabrique, {bool page = false}) {
    group(nom, () {
      for (final echelle in echelles) {
        for (final largeur in largeurs) {
          testWidgets('échelle $echelle · largeur ${largeur.toInt()} px',
              (tester) async {
            await rendre(tester, fabrique(),
                echelle: echelle, largeur: largeur, page: page);

            expect(tester.takeException(), isNull);
          });
        }
      }
    });
  }

  batterie('PwButton — libellé long', () => const PwButton(
    label: 'Créer un compte gratuit pour continuer',
    icon: Icons.person_add_rounded,
  ));

  batterie('PwButton — en chargement', () => const PwButton(
    label: 'Envoi de la preuve de paiement en cours',
    isLoading: true,
  ));

  batterie('ConfidenceIndicator', () => const Padding(
    padding: EdgeInsets.all(12),
    child: ConfidenceIndicator(score: 87),
  ));

  batterie('ErreurChargement', () => ErreurChargement(
    erreur: Exception('délai dépassé'),
    onRetry: () {},
    quoi: 'les pronostics du jour',
  ));

  batterie('GuestLockedView', () => const GuestLockedView(
    icon: Icons.lock_outline_rounded,
    title: 'Réservé aux membres inscrits',
    message: 'Crée un compte gratuit pour suivre tes paris, consulter ton '
             'historique et recevoir les alertes de tes matchs favoris.',
    from: '/bankroll',
  ), page: true);
}
