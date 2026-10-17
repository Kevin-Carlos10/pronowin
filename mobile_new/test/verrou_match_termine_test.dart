import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/verrou_pronostic.dart';

/// Un pronostic Premium se verrouille par une seule règle partagée.
///
/// Jusqu'au 17 octobre 2026, un pronostic payant cessait de l'être une fois
/// le match joué ; depuis, il reste verrouillé pour un non-abonné (décision de
/// l'utilisateur, « visible mais verrouillé »). Ce qui suit raconte pourquoi
/// la règle est partagée. Le serveur l'applique depuis `verrou_pronostic.ts`
/// — mais elle s'arrêtait à la frontière du réseau. Cinq écrans calculaient
/// leur propre cadenas avec `isPremium && !utilisateurPremium`, sans jamais
/// regarder le statut du match. Sur une fiche de match terminé, l'application
/// affichait donc le score, les cotes et le pronostic, puis « Débriefing du
/// modèle » sous un cadenas : elle ouvrait tout sauf ce qui expliquait le
/// reste.
///
/// Le cas le plus retors était `match_detail_page.dart` :
///
///     final isLocked = match.isLocked || (match.isPremium && !isPremium);
///
/// Le premier terme venait du serveur, qui appliquait la règle ; le second la
/// contredisait. Entre les deux, un `||` donne toujours raison à celui qui
/// verrouille — la correction serveur ne pouvait pas atteindre l'écran.
void main() {
  group('la règle', () {
    test('verrouille un premium pour un non-abonné, avant comme après le match', () {
      expect(estVerrouille(estPremium: true, utilisateurPremium: false), isTrue);
    });

    test('les deux autres portes restent ouvertes', () {
      // Sans elles, une règle qui verrouillerait tout passerait le premier
      // test sans rien servir.
      expect(estVerrouille(estPremium: false, utilisateurPremium: false), isFalse);
      expect(estVerrouille(estPremium: true, utilisateurPremium: true), isFalse);
    });
  });

  test('aucun écran de match ne calcule son propre cadenas', () {
    // Le motif est celui qui a divergé : « premium et pas abonné », sans le
    // statut.
    //
    // Deux exemptions, chacune pour une raison qui tient :
    //
    //   - `compte_a_rebours.dart` : c'est le décompte d'un match à venir, où
    //     « terminé » est faux par construction ;
    //
    //   - `pronostics_page.dart` : la carte de l'onglet « Pour Toi », dont la
    //     route porte `premiumMiddleware` côté serveur. L'utilisateur y est
    //     donc toujours abonné, et le cadenas ne peut pas se déclencher. Le
    //     modèle `ForYouProno` ne transporte d'ailleurs aucun statut de match :
    //     appliquer la règle ici demanderait de l'étendre. SI LA ROUTE S'OUVRE
    //     AUX COMPTES GRATUITS, il faudra faire les deux.
    const exempts = ['compte_a_rebours.dart', 'pronostics_page.dart'];
    final motif = RegExp(
      r'isPremium\s*&&\s*!\s*(widget\.)?(is|user)Premium', caseSensitive: false);

    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final chemin = f.path.replaceAll('\\', '/');
      if (exempts.any(chemin.endsWith)) continue;
      // Les tutoriels ne sont pas des matchs : « terminé » n'a pas de sens.
      if (chemin.contains('/tutoriels/')) continue;

      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        if (lignes[i].trimLeft().startsWith('//')) continue;
        if (motif.hasMatch(lignes[i])) {
          fautes.add('$chemin:${i + 1} ${lignes[i].trim()}');
        }
      }
    }

    expect(fautes, isEmpty,
      reason: 'cet écran recalcule son propre cadenas au lieu de la règle '
              'partagée : les deux finiront par diverger');
  });
}
