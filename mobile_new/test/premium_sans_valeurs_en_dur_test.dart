import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Ce que le module Premium n'a plus le droit de contenir.
///
/// Chacune de ces valeurs a réellement menti à l'utilisateur : un prix de
/// 5 000 FCFA qui n'existait dans aucune formule, un numéro de réception
/// compilé dans le binaire qui contournait une protection du serveur, quatre
/// copies manuelles du délai de validation, une liste de quatre opérateurs
/// alors qu'un seul était publié, et un effectif d'utilisateurs inventé.
///
/// Aucune n'aurait été détectée par le compilateur, l'analyseur ou un test
/// d'interface : l'écran s'affichait parfaitement. D'où ce garde-fou textuel.
void main() {
  final module = <String, String>{};

  setUpAll(() {
    const fichiers = {
      'activer_premium': 'lib/features/abonnement/presentation/pages/activer_premium_page.dart',
      'gate_sheet':      'lib/shared/widgets/premium_gate_sheet.dart',
      'fournisseur':     'lib/features/abonnement/presentation/providers/subscription_provider.dart',
    };
    for (final e in fichiers.entries) {
      final f = File(e.value);
      if (!f.existsSync()) fail('Fichier introuvable : ${e.value}');
      module[e.key] = f.readAsStringSync();
    }
  });

  /// Le code seul : sans les commentaires, qui citent volontairement les
  /// valeurs supprimées pour expliquer pourquoi elles l'ont été.
  String codeSeul(String source) => source
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  test('aucun numéro de réception n\'est compilé dans le binaire', () {
    for (final e in module.entries) {
      expect(RegExp(r"""['"]\+?22\d{9,}['"]""").hasMatch(codeSeul(e.value)), isFalse,
        reason: '${e.key} : un numéro en dur annule le filtrage du serveur, '
                'qui refuse volontairement de publier un numéro non configuré');
    }
  });

  test('le prix d\'accroche n\'est pas écrit à la main', () {
    expect(RegExp(r"""['"]\s*\d[\d   ]*\s*FCFA""").hasMatch(codeSeul(module['gate_sheet']!)),
      isFalse,
      reason: 'la feuille annonçait « 5 000 FCFA », un tarif qui '
              'n\'existait dans aucune formule — il se calcule désormais');
  });

  test('le délai de validation n\'est plus recopié dans les écrans', () {
    final code = codeSeul(module['activer_premium']!);
    final copies = RegExp(r'\d+\s*(?:min|minutes|h|heures?)\s+ouvrabl')
        .allMatches(code).length;
    expect(copies, 0,
      reason: 'le délai vient de `review_delay_direct` / `review_delay_code` ; '
              'il en existait quatre copies manuelles, qui restaient toutes '
              'sur l\'ancienne valeur quand le serveur changeait');
  });

  test('la durée offerte n\'est pas écrite à la main', () {
    // Le parcours « code promo » donnait −30 % ; il offre désormais le premier
    // mois. Le chiffre vient du serveur (`code_offer_days`) : écrit en dur, il
    // aurait promis un mois pendant que le serveur en accordait quinze jours.
    final code = codeSeul(module['activer_premium']!);

    expect(RegExp(r'-\s*30\s*%').hasMatch(code), isFalse,
      reason: 'la remise n\'existe plus');
    expect(RegExp(r"""['"]\s*1\s*mois offert""").hasMatch(code), isFalse,
      reason: 'le libellé se construit depuis `joursOffreCode`');
    expect(code.contains('libelleOffreCode'), isTrue);
  });

  test('la liste des opérateurs n\'est pas figée', () {
    final code = codeSeul(module['activer_premium']!);
    // Deux noms d'opérateurs sur la même ligne = une liste écrite à la main.
    final fige = RegExp(
      r'(Orange Money|Wave|Moov|MTN|Telecel)[^\n]{0,24}(Orange Money|Wave|Moov|MTN|Telecel)');
    expect(fige.hasMatch(code), isFalse,
      reason: 'l\'écran annonçait « Orange Money · Wave · MTN · Moov » pendant '
              'que le serveur n\'en publiait qu\'un — et MTN n\'opère pas au '
              'Burkina Faso');
  });

  test('aucun effectif d\'utilisateurs n\'est affirmé sans mesure', () {
    final code = codeSeul(module['activer_premium']!);
    expect(RegExp(r"""['"]\s*\d+\s?[KkMm]\+""").hasMatch(code), isFalse,
      reason: '« 2K+ Utilisateurs Actifs » était écrit en dur, avec trois faux '
              'avatars — même famille que le « N°1 en Afrique de l\'Ouest »');
    expect(code.contains('Utilisateurs Actifs'), isFalse);
  });

  test('les montants FCFA passent par le formateur partagé', () {
    final code = codeSeul(module['activer_premium']!);
    expect(RegExp(r'toStringAsFixed\(0\)\}?\s*FCFA').hasMatch(code), isFalse,
      reason: 'sans `montantExact`, l\'écran affiche « 54000 » là où '
              'l\'utilisateur doit recopier un montant');
    expect(code.contains('montantExact('), isTrue,
      reason: 'le formateur doit être réellement appelé');
  });

  test('les tarifs de repli ne sont plus dupliqués dans les écrans', () {
    final code = codeSeul(module['activer_premium']!);
    for (final montant in ['6000', '54000', '4200', '37800']) {
      expect(RegExp('\\?\\?\\s*$montant\\b').hasMatch(code), isFalse,
        reason: 'le repli $montant appartient à TarifsPremium ; en garder une '
                'copie ici recrée deux sources de vérité qui divergent');
    }
  });
}
