import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/installateur_maj.dart';

/// La permission d'installer ne doit exister que dans la variante directe.
///
/// L'APK du site télécharge et installe lui-même ses mises à jour, ce qui exige
/// `REQUEST_INSTALL_PACKAGES`. Le paquet publié sur Google Play ne le peut pas :
/// la politique « Device and Network Abuse » réserve l'installation d'APK hors
/// Play aux boutiques d'applications. Sa présence dans un AAB n'est pas une
/// mise à jour refusée, c'est un motif de retrait.
///
/// Un drapeau Dart ne pouvait pas faire cette différence : il ne touche pas au
/// manifeste. D'où deux `productFlavors`, dont une seule fusionne
/// `src/direct/AndroidManifest.xml`.
///
/// ── Deux contrôles, deux moments ───────────────────────────────────────────
///
/// Celui-ci lit les sources : il attrape la permission déplacée dans
/// `src/main`, ou les variantes supprimées, au moment où c'est écrit.
/// `tool/verifier_bundle.py` ouvre l'artefact produit et regarde ce qu'il
/// contient vraiment — c'est lui qui attrape un build lancé sans `--flavor`.
///
/// Les deux sont nécessaires. La leçon du 10 septembre est qu'un défaut qui ne
/// vit que dans le binaire ne se voit qu'en ouvrant le binaire ; celle d'avant
/// est qu'un contrôle qui n'existe qu'à la fin arrive trop tard.
void main() {
  const direct = 'android/app/src/direct/AndroidManifest.xml';
  const principal = 'android/app/src/main/AndroidManifest.xml';
  const gradle = 'android/app/build.gradle.kts';
  const permission = 'REQUEST_INSTALL_PACKAGES';

  String lire(String chemin) {
    final f = File(chemin);
    expect(f.existsSync(), isTrue, reason: '$chemin introuvable');
    return f.readAsStringSync();
  }

  test('la variante directe déclare la permission', () {
    expect(lire(direct), contains(permission),
        reason: 'sans elle, l\'écran de mise à jour télécharge soixante-dix '
                'mégaoctets puis échoue à les installer');
  });

  test('le manifeste commun ne la déclare pas', () {
    // Contrepartie du contrôle précédent, et le vrai risque : déplacer la
    // permission dans `src/main` « pour simplifier » la mettrait dans l'AAB
    // sans que rien ne change à l'écran.
    expect(lire(principal), isNot(contains(permission)),
        reason: 'la permission passerait alors dans le paquet Google Play');
  });

  test('aucune variante play ne la déclare', () {
    final dossier = Directory('android/app/src/play');
    if (!dossier.existsSync()) return;
    for (final f in dossier.listSync(recursive: true).whereType<File>()) {
      expect(f.readAsStringSync(), isNot(contains(permission)),
          reason: '${f.path} déclare la permission dans la variante des '
                  'boutiques');
    }
  });

  test('les deux variantes existent', () {
    // Sans elles, `src/direct` n'est fusionné nulle part : la permission
    // disparaîtrait des deux paquets, et la mise à jour directe échouerait à
    // l'installation — après le téléchargement, au pire moment.
    final g = lire(gradle);
    expect(g, contains('productFlavors'));
    expect(g, contains('create("direct")'));
    expect(g, contains('create("play")'));
  });

  test('le script de build choisit la variante et la fait vérifier', () {
    final script = File('tool/build.ps1').readAsStringSync();
    expect(script, contains(r'--flavor $Canal'),
        reason: 'un build sans --flavor ne fusionne aucune variante');
    expect(script, contains(r"verifier_bundle.py') $sortie $Canal"),
        reason: 'le vérificateur doit savoir quel canal il contrôle, sinon il '
                'ne peut rien dire de la permission');
  });

  test('le vérificateur d\'artefact connaît la permission', () {
    expect(File('tool/verifier_bundle.py').readAsStringSync(),
        contains(permission),
        reason: 'le contrôle sur les sources ne voit pas un build lancé à la '
                'main sans --flavor ; seul l\'artefact le dit');
  });

  test('le canal natif porte le même nom des deux côtés', () {
    // Un renommage d'un seul côté ne casse pas la compilation : l'appel
    // remonte en `MissingPluginException`, que le service rattrape — et
    // l'installation échoue en silence, après le téléchargement.
    final kotlin = File(
      'android/app/src/main/kotlin/com/pronowin/app/InstallateurApk.kt',
    ).readAsStringSync();
    expect(kotlin, contains('"${InstallateurMaj.canal.name}"'),
        reason: 'le nom du canal diffère entre Dart et Kotlin');
  });
}
