import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// L'onboarding ne promet que ce que le compte gratuit obtient.
///
/// C'est le premier écran vu, avant même la création du compte — donc le
/// moment où une promesse fausse coûte le plus cher : elle est vérifiée dans
/// la minute qui suit, et par tout le monde.
///
/// Trois affirmations y vivaient :
///
///   « Une communauté qui partage ses analyses »
///   « Rejoins une communauté qui analyse avant de miser »
///     → `comments.routes.ts` porte `premiumMiddleware` sur ses trois routes.
///       Un compte gratuit reçoit un 403.
///
///   « Accès gratuit à **tous** les pronostics du jour »
///     → `estVerrouille()` garde les pronostics Premium fermés tant que le
///       match n'est pas terminé.
///
/// La communauté reste un avantage Premium : c'est donc le texte qui s'aligne
/// sur le produit, et elle devient un argument de vente au lieu d'une promesse
/// démentie à la première ouverture.
void main() {
  final fichier = File('lib/features/onboarding/presentation/pages/'
                       'onboarding_page.dart');

  /// Les lignes de code, sans les commentaires.
  ///
  /// Ceux-ci citent les anciennes formulations pour expliquer le défaut. Un
  /// contrôle qui se valide sur sa propre prose ne contrôle rien — la leçon a
  /// déjà servi plusieurs fois dans ce dépôt.
  final lignes = fichier
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .toList();

  group('promesses de l\'onboarding', () {
    test('la communauté n\'est jamais promise sans nommer Premium', () {
      // Elle peut être citée — c'est même un bon argument. Mais jamais seule :
      // le lecteur doit savoir qu'elle se paie.
      final fautives = lignes
          .where((l) => l.toLowerCase().contains('communaut'))
          .where((l) => !l.contains('Premium'))
          .toList();

      expect(fautives, isEmpty,
        reason: 'la communauté est réservée au Premium, mais promise sans le '
                'dire :\n${fautives.join('\n')}');
    });

    test('aucune promesse de « tous les pronostics » au compte gratuit', () {
      // Le gratuit voit tous les pronostics *gratuits* — sans quota, aucun
      // n'étant appliqué dans le code. Il ne voit pas les Premium tant que le
      // match n'est pas terminé. Le mot « gratuits » fait toute la différence.
      final fautives = lignes
          .where((l) => RegExp(r'[Tt]ous les pronostics').hasMatch(l))
          .where((l) => !l.contains('gratuits'))
          .toList();

      expect(fautives, isEmpty,
        reason: 'promesse trop large — les pronostics Premium restent '
                'verrouillés :\n${fautives.join('\n')}');
    });

    test('le contre-test : la mention Premium de la communauté existe bien', () {
      // Sans cela, les deux contrôles ci-dessus passeraient aussi en effaçant
      // simplement toute mention de la communauté — ce qui priverait l'écran
      // d'un argument réel au lieu de le rendre exact.
      expect(
        lignes.any((l) => l.contains('Premium') &&
                          l.toLowerCase().contains('communaut')),
        isTrue,
        reason: 'la communauté ne devrait pas disparaître : elle se vend',
      );
    });
  });
}
