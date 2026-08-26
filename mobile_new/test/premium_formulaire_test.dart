import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Trois défauts du formulaire de paiement, chacun invisible à la compilation.
///
///  1. Le champ « Montant exact que vous avez envoyé » était **pré-rempli**
///     avec le montant attendu. Personne ne le modifiait : le déclaré valait
///     donc toujours l'attendu, et la comparaison faite en administration ne
///     pouvait rien détecter — ni un envoi partiel, ni des frais
///     transfrontaliers.
///  2. La numérotation commençait à « 1. Montant envoyé » alors que la
///     première action réelle, le transfert, figurait au-dessus sans numéro.
///  3. Aucune sortie de secours : qui avait payé puis perdu sa capture
///     restait devant un bouton désactivé, sans interlocuteur.
void main() {
  late String page;
  late String contact;

  setUpAll(() {
    const p = 'lib/features/abonnement/presentation/pages/activer_premium_page.dart';
    const c = 'lib/core/config/contact_support.dart';
    for (final f in [p, c]) {
      if (!File(f).existsSync()) fail('Fichier introuvable : $f');
    }
    page    = File(p).readAsStringSync();
    contact = File(c).readAsStringSync();
  });

  String codeSeul(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  group('le montant déclaré peut diverger de l\'attendu', () {
    test('le champ n\'est jamais pré-rempli avec le tarif', () {
      expect(
        RegExp(r'_amountCtrl\.text\s*=\s*_fcfa').hasMatch(codeSeul(page)),
        isFalse,
        reason: 'pré-remplir le champ de vérification le rend inopérant : '
                'déclaré et attendu ne peuvent plus différer');
    });

    test('aucun repli silencieux ne remplace un montant absent', () {
      expect(
        RegExp(r'tryParse\(_amountCtrl\.text[^)]*\)\s*\?\?\s*_fcfa')
            .hasMatch(codeSeul(page)),
        isFalse,
        reason: 'retomber sur le tarif attendu quand le champ est vide '
                'reconstitue exactement le défaut corrigé');
    });

    test('une soumission sans montant est refusée', () {
      final code = codeSeul(page);
      expect(code.contains('_montantSaisi'), isTrue,
        reason: 'le montant doit conditionner l\'envoi, comme la capture');
      expect(RegExp(r'montant\s*==\s*null\s*\|\|\s*montant\s*<=\s*0')
          .hasMatch(code), isTrue,
        reason: 'la garde côté action doit exister aussi : le bouton peut '
                'être contourné par un changement d\'état');
    });

    test('un écart est signalé à l\'utilisateur', () {
      // Vérifier la simple présence du nom laissait passer le cas où la classe
      // existe mais n'est plus instanciée — la déclaration suffisait à rendre
      // le contrôle vert. On exige l'appel, avec ses arguments.
      expect(RegExp(r'_AlerteEcartMontant\(\s*saisi:').hasMatch(codeSeul(page)),
        isTrue,
        reason: 'un écart découvert deux heures plus tard par '
                'l\'administrateur ne peut plus être corrigé par l\'envoyeur');
    });
  });

  group('la numérotation compte à partir de la première action', () {
    test('le transfert porte un numéro', () {
      expect(RegExp(r'\$\{?widget\.etape\}?\.\s*Envoie').hasMatch(codeSeul(page)),
        isTrue,
        reason: 'envoyer l\'argent est l\'étape 1 ; elle n\'en portait aucune');
    });

    test('les étapes suivantes ne se chevauchent plus', () {
      final code = codeSeul(page);
      final decalages = RegExp(r'etapeTransfert \+ (\d+)')
          .allMatches(code).map((m) => m.group(1)!).toList();
      expect(decalages, ['1', '2', '3'],
        reason: 'deux champs partageaient le décalage « +1 » et portaient donc '
                'le même numéro');
    });

    test('le parcours par code promo ne demande plus de transfert', () {
      // Ce test exigeait `etapeTransfert: 3` — l'onglet code promo comptait
      // deux étapes avant le versement. Le versement a disparu : ce parcours
      // n'échange plus d'argent, il offre le premier mois contre la preuve du
      // dépôt chez le partenaire. Réclamer un montant et un numéro Mobile
      // Money y serait devenu incompréhensible.
      final code = codeSeul(page);

      expect(code.contains('etapeTransfert: 3'), isFalse);
      expect(RegExp(r'_buildPaymentFieldsSection\(isCode:\s*true')
          .hasMatch(code), isFalse,
        reason: 'aucun champ de paiement sur un parcours sans paiement');
    });

    test('la soumission du code promo n\'envoie ni montant ni numéro', () {
      // La garde porte sur l'appel, pas sur le formulaire : masquer les champs
      // en continuant d'envoyer leurs valeurs laisserait le serveur croire à
      // un paiement.
      final code = codeSeul(page);
      final debut = code.indexOf('Future<void> _submitCode()');
      expect(debut, greaterThan(-1));
      final corps = code.substring(debut, code.indexOf('Future<String?> _toBase64'));

      expect(corps.contains('amount:'), isFalse);
      expect(corps.contains('senderPhone:'), isFalse);
      expect(corps.contains('paymentImageBase64:'), isFalse);
      expect(corps.contains('planId:'), isFalse,
        reason: 'l\'offre porte une durée fixe, pas une formule choisie ici');
      // Et ce qui la justifie reste exigé.
      expect(corps.contains('xbetId:'), isTrue);
      expect(corps.contains('platform:'), isTrue);
    });
  });

  group('qui a déjà payé n\'est jamais dans une impasse', () {
    test('une sortie de secours existe', () {
      expect(codeSeul(page).contains('_SortieDeSecours'), isTrue);
    });

    test('elle est offerte sur les deux onglets', () {
      // La virgule finale distingue les deux usages de la déclaration du
      // constructeur, `const _SortieDeSecours();`, qui se terminait par un
      // point-virgule et faussait le compte.
      expect(RegExp(r'_SortieDeSecours\(\)\s*,').allMatches(codeSeul(page)).length, 2,
        reason: 'le parcours code promo mène au même cul-de-sac');
    });

    test('elle mène au support, avec une demande déjà rédigée', () {
      final code = codeSeul(page);
      expect(code.contains('ContactSupport.ouvrirEmail'), isTrue);
      expect(code.contains('sujet:'), isTrue,
        reason: 'un objet vide oblige le support à réclamer le contexte avant '
                'de pouvoir chercher la transaction');
    });

    test('l\'adresse du support n\'est écrite qu\'à un seul endroit', () {
      expect(codeSeul(page).contains('@gmail.com'), isFalse,
        reason: 'une seconde copie de l\'adresse finit par diverger, et c\'est '
                'celle qui n\'est plus relevée qui reçoit les urgences');
      expect(contact.contains('@'), isTrue);
    });
  });
}
