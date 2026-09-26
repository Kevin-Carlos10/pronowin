import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'écran de suppression ne doit pas promettre plus que le serveur ne fait.
///
/// `DELETE /profile` **anonymise** : il vide les champs personnels (téléphone,
/// e-mail, empreinte du mot de passe, pseudo, nom, avatar, jeton de
/// notification, date de naissance), met `isActive` à faux, horodate
/// `deletedAt` et révoque les jetons de session. La ligne utilisateur reste,
/// avec l'historique de paris, la bankroll et les parrainages.
///
/// L'application annonçait pourtant trois choses fausses, dont une
/// dangereuse :
///
///   - « Effacer définitivement tes données » sur le bouton lui-même ;
///   - « Ton historique sera effacé définitivement » ;
///   - « Ton abonnement Premium sera annulé ».
///
/// La troisième est celle qui coûte. La suppression ne touche ni
/// `subscriptionPlan` ni `subscriptionExpiresAt`, et aucune résiliation n'est
/// appelée nulle part : en facturation Google Play, seul Google peut résilier.
/// Quelqu'un qui supprimait son compte pour cesser de payer continuait d'être
/// débité — après avoir lu le contraire sur l'écran qui le lui demandait.
/// C'est l'avertissement censé le protéger qui causait le prélèvement.
///
/// Ce contrôle est textuel : la fenêtre est un widget privé, et le dépôt garde
/// déjà ses surfaces privées ainsi (`canal_store_test.dart`).
/// `tool/injections_suppression.py` vérifie qu'il mord.
void main() {
  const chemin = 'lib/features/parametres/presentation/pages/parametres_page.dart';
  final lignes = File(chemin).readAsLinesSync();

  /// Les lignes de code, commentaires exclus — ceux-ci citent les phrases
  /// fautives pour les expliquer.
  Iterable<MapEntry<int, String>> code() sync* {
    for (var i = 0; i < lignes.length; i++) {
      final l = lignes[i];
      if (l.trimLeft().startsWith('//')) continue;
      yield MapEntry(i + 1, l);
    }
  }

  test('l\'écran de suppression existe toujours', () {
    // Sans cette ancre, les contrôles suivants verdiraient sur un fichier
    // renommé ou vidé.
    expect(lignes.join('\n'), contains('_DeleteAccountSheet'));
    expect(lignes.join('\n'), contains('_DeleteWarning'));
  });

  test('aucune promesse d\'effacement définitif', () {
    // Le premier jet employait `\w*` entre le verbe et l'adverbe. En Dart,
    // `\w` vaut [A-Za-z0-9_] : il ne couvre pas les lettres accentuées, et
    // « effacé définitivement » — la formulation exacte du défaut — lui
    // échappait. Le banc d'injection l'a dit : « NON DETECTE ».
    //
    // Deux conditions valent mieux qu'une expression trop savante : la ligne
    // porte l'adverbe, et elle porte le verbe.
    final fautes = code()
        .where((e) {
          final l = e.value.toLowerCase();
          return l.contains('définitivement') &&
                 (l.contains('effac') || l.contains('supprim'));
        })
        .map((e) => '$chemin:${e.key} ${e.value.trim()}')
        .toList();

    expect(fautes, isEmpty,
      reason: 'le serveur anonymise, il n\'efface pas : cette promesse est '
              'celle que l\'on cite pour exercer un droit à l\'effacement');
  });

  test('aucune promesse de résiliation automatique', () {
    final fautes = code()
        .where((e) => RegExp(
              r"abonnement[^']*(sera|est)\s+(annulé|annule|résilié|resilie)",
              caseSensitive: false,
            ).hasMatch(e.value))
        .map((e) => '$chemin:${e.key} ${e.value.trim()}')
        .toList();

    expect(fautes, isEmpty,
      reason: 'rien ne résilie l\'abonnement : le promettre laisse '
              'l\'utilisateur se faire débiter après avoir cru y couper');
  });

  test('l\'utilisateur est renvoyé vers le store pour résilier', () {
    // La formulation exacte peut évoluer ; l'information, non. Sans elle,
    // l'écran se contente de ne plus mentir — il n'aide pas.
    expect(lignes.join('\n'), contains('Play Store'),
      reason: 'en canal store, la seule façon de résilier est le Play Store : '
              'l\'écran doit le dire');
  });
}
