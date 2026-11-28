import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'aides/code_seul.dart';

/// Où vit « Réinitialiser le solde », et ce que sa confirmation annonce.
///
/// ── Ce qui était affiché ──────────────────────────────────────────────────
///
/// Un bouton pleine largeur, cerclé de rouge, entre le bilan et les filtres —
/// aussi visible qu'une action principale. Il efface pourtant un suivi, et le
/// serveur n'autorise l'opération qu'une fois tous les trente jours.
///
/// Il a rejoint la feuille de réglages, derrière l'icône de l'en-tête où l'on
/// va déjà changer son budget.
///
/// ── Ce que la confirmation taisait ────────────────────────────────────────
///
/// Elle disait : « Ton solde sera remis à ton budget initial. L'historique des
/// paris reste conservé. » Deux omissions, et la seconde touche aux chiffres :
///
///   - le **délai de trente jours**, appliqué par le serveur, que
///     l'utilisateur ne découvrait qu'au refus suivant ;
///   - le **sort des paris en cours**. Repartir du budget entier rembourse
///     leur mise, que le règlement crédite ensuite une seconde fois. Mise de
///     2 000 à la cote 2 sur 10 000 : le gain menait à 14 000 au lieu de
///     12 000, et une défaite ne coûtait plus rien.
///
/// La correction serveur est tenue par `reinitialisation_bankroll.test.ts` ;
/// ce banc-ci tient ce que l'écran en dit.
void main() {
  late String page;

  /// Le texte de la boîte de confirmation, isolé du reste du fichier.
  ///
  /// Une première version cherchait « 30 jours » dans la page entière. Le
  /// sous-titre du réglage contient la même mention : retirer le délai de la
  /// confirmation laissait donc le contrôle vert, alors que c'est précisément
  /// là qu'il doit être lu — au moment de décider.
  late String confirmation;

  setUpAll(() {
    page = File('lib/features/bankroll/presentation/pages/bankroll_page.dart')
        .readAsStringSync()
        .pipeCodeSeul();

    final debut = page.indexOf('_confirmReset(BuildContext');
    expect(debut, greaterThan(-1), reason: '_confirmReset est introuvable');
    confirmation = page.substring(debut, page.indexOf('actions:', debut));
  });

  group('le geste est rangé dans les réglages', () {
    test('il n\'est plus dans le flux de la page', () {
      // La carte de solde ne le reçoit plus : le paramètre a disparu avec le
      // bouton, pour qu'aucun appelant ne puisse le replacer par mégarde.
      expect(page, isNot(contains('onReset:     ()')),
          reason: 'le bouton est revenu entre le bilan et les filtres');
    });

    test('la feuille de réglages le propose', () {
      expect(page, contains('_BudgetSheet('));
      expect(page, contains('widget.onReset'),
          reason: 'sans lui, le geste n\'est plus atteignable du tout');
    });

    test('et seulement quand une bankroll existe', () {
      // Le proposer avant toute configuration n'aurait rien à réinitialiser.
      expect(page, contains('widget.existing != null && widget.onReset != null'));
    });
  });

  group('la confirmation dit ce qui va se passer', () {
    test('elle annonce le délai de trente jours', () {
      expect(confirmation, contains('30 jours'),
          reason: 'le serveur refuse pendant trente jours ; le découvrir '
              'après coup transforme un réglage en panne');
    });

    test('elle annonce le sort des mises en jeu', () {
      expect(confirmation, contains('moins les mises encore'),
          reason: 'c\'est la différence entre un solde juste et un solde '
              'gonflé de la mise à chaque pari en cours');
    });

    test('elle ne promet plus le budget entier', () {
      // La phrase d'origine, mot pour mot : elle décrivait le comportement
      // qui faussait les chiffres.
      expect(confirmation, isNot(contains('sera remis à ton budget initial')));
    });
  });
}
