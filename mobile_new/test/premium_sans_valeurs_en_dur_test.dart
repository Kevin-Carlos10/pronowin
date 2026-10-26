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

  test("le bouton vers le partenaire porte le lien d'affiliation", () {
    // Le plus coûteux des liens en dur, et le plus silencieux.
    //
    // La refonte ajoute « Ouvrir 1xBet » sur l'écran qui demande d'ouvrir un
    // compte — l'endroit exact où se joue la commission. Une adresse écrite
    // ici ouvrirait la même page, l'utilisateur s'inscrirait, et personne ne
    // serait crédité : aucune erreur, aucun écran cassé, et un manque qui ne
    // se découvre qu'au relevé, des semaines plus tard.
    //
    // `BookmakerAffiliation.ouvrir` porte l'identifiant de compte et
    // l'étiquette de campagne, et vient du serveur.
    final code = codeSeul(module['activer_premium']!);

    expect(code, isNot(contains('1xbet.com')),
      reason: 'une adresse partenaire en dur ne crédite personne');
    expect(code, contains('BookmakerAffiliation.ouvrir'),
      reason: "l'ouverture doit passer par le lien d'affiliation publié");
  });

  test('le délai de validation vient du serveur', () {
    // Cinquième copie évitée. Quatre écritures manuelles de ce délai ont déjà
    // été retirées de cet écran, dont une qui annonçait « 2h » sans lien avec
    // la valeur réelle. La refonte le rapproche du bouton d'envoi, là où la
    // question se pose — la tentation de l'écrire à la main y est maximale.
    final code = codeSeul(module['activer_premium']!);

    expect(code, contains('delaiCode'),
      reason: 'le délai affiché doit être celui que le serveur publie');
    expect(RegExp("[0-9]+ (minutes|heures) ouvrables").hasMatch(code), isFalse,
      reason: 'un délai écrit à la main dément le serveur sans le savoir');
  });

  test('rien n\'est lu sur la carte de route en direct', () {
    // Le défaut le plus coûteux de cet écran, et le plus discret.
    //
    // Tarifs, code promo et moyens de paiement venaient de `subData`, passé en
    // `extra` au moment de pousser la route. Cinq chemins mènent ici ; un seul
    // la passait. Ouvert depuis l'onglet Performance, depuis la feuille de
    // blocage, ou au retour de « compléter le profil », l'écran annonçait
    // « Offre momentanément indisponible » et « Momentanément indisponible »,
    // et affichait « $10 » — le repli `?? 10`, pas un tarif.
    //
    // Rien ne le signalait : ces messages d'indisponibilité existent exprès,
    // donc un écran entièrement vide passait pour un écran honnête, alors que
    // `PROMO_CODE` était en base et publié par l'API.
    //
    // La correction a d'abord porté sur les FCFA, et les quatre prix en
    // dollars sont restés en arrière avec leurs propres replis. C'est
    // exactement ce que ce contrôle empêche de se reproduire, champ par champ.
    final code = codeSeul(module['activer_premium']!);

    final lectures = RegExp(r'widget\.subData\s*\??\[')
        .allMatches(code)
        .length;
    expect(lectures, 0,
      reason: 'un champ est relu sur la carte de route : il sera vide pour '
              'les quatre chemins qui ne la passent pas. Tout doit passer '
              'par `_donnees`, qui interroge le serveur d\'abord');

    expect(code, contains('currentSubscriptionProvider'),
      reason: 'l\'écran doit tenir ses données du serveur, pas de qui l\'ouvre');
  });
}
