import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/widgets/ecran_mise_a_jour.dart';

/// Le fond de l'écran de mise à jour.
///
/// ── Ce qu'il est, et ce qu'il n'est pas ───────────────────────────────────
///
/// La maquette fournie contenait **tout** l'écran : la photo, mais aussi le
/// panneau sombre, le titre, le bouton orange et « Plus tard ». La poser
/// telle quelle en fond aurait affiché deux titres et deux boutons, dont l'un
/// peint dans l'image — inerte, et impossible à distinguer du vrai.
///
/// L'asset est donc la maquette **recadrée** : la photo seule. Le reste est
/// redessiné par l'application, où il peut réagir.
///
/// ── Pourquoi le poids compte ici ──────────────────────────────────────────
///
/// Cette application se distribue en APK de 68 Mo, par données mobiles, dans
/// un pays où elles se paient. La photo pesait 1,4 Mo en PNG et 138 Ko en
/// WebP : le même écran, dix fois moins cher à livrer.
///
/// Un contrôle de poids paraît tatillon jusqu'au jour où quelqu'un remplace
/// l'image par l'export brut d'un outil de design — ce qui ne casse rien,
/// ne se voit pas à l'écran, et alourdit chaque téléchargement.
void main() {
  const chemin = 'assets/images/maj_fond.webp';

  test('l\'image existe là où l\'écran la cherche', () {
    expect(File(chemin).existsSync(), isTrue,
        reason: 'sans elle l\'écran retombe sur un fond uni : lisible, mais '
            'ce n\'est plus la page demandée');
  });

  test('elle reste légère', () {
    final ko = File(chemin).lengthSync() / 1024;
    expect(ko, lessThan(400),
        reason: 'la photo pèse 138 Ko en WebP ; au-delà de 400, c\'est un '
            'export brut qui a repris sa place');
  });

  test('l\'écran s\'y réfère', () {
    final source =
        File('lib/core/widgets/ecran_mise_a_jour.dart').readAsStringSync();
    expect(source, contains(chemin));
  });

  testWidgets('elle est réellement montée dans l\'arbre', (tester) async {
    // Le contrôle de source seul laisserait passer un chemin écrit dans un
    // commentaire, ou une image construite puis jamais insérée.
    await tester.pumpWidget(const MaterialApp(
      home: EcranMiseAJour(
        message: 'Une nouvelle version est disponible.',
        bloquant: false,
        lien: 'https://pronowin.space/downloads/app-release.apk',
        installationDirecte: true,
      ),
    ));
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName);
    expect(images, contains(chemin));
  });
}
