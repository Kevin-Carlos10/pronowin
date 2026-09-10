import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/abonnement/domain/tarifs_premium.dart';

/// Le défaut d'origine : la feuille d'accroche annonçait « À partir de
/// 5 000 FCFA / mois », écrit en dur, alors qu'aucun tarif du système ne valait
/// 5 000. L'utilisateur tapait, et découvrait 6 000.
void main() {
  // Espace insécable fine émise par `montantExact` — un espace ordinaire ici
  // ferait échouer la comparaison pour une raison invisible à la lecture.
  const fine = ' ';

  const complet = {
    'premium_price_monthly_fcfa': 6000,
    'premium_price_annual_fcfa':  54000,
    // Le parcours « code promo » n'a plus de tarif : il offre le premier mois.
    'code_offer_days':            30,
    'promo_code':          'CODE2030',
    'review_delay_direct': '15 minutes ouvrables',
    'review_delay_code':   '1 heure ouvrable',
    'betting_platforms':   ['1xbet', 'melbet'],
    'payment_methods': [
      {'key': 'orange_money', 'label': 'Orange Money', 'phone': '22645568158'},
      {'key': 'wave',         'label': 'Wave',         'phone': '22670000000'},
    ],
  };

  group('« à partir de » annonce un prix qui existe', () {
    test('le minimum est le meilleur tarif mensuel équivalent', () {
      final t = TarifsPremium.depuis(complet);
      // 6 000 mensuel · 54 000/12 = 4 500 ramené au mois
      expect(t.minMensuel, 4500);
      expect(t.minMensuelFormate, '4${fine}500');
    });

    test('le minimum correspond toujours à un tarif réellement proposé', () {
      final t = TarifsPremium.depuis(complet);
      final proposes = {t.mensuelDirect, (t.annuelDirect / 12).round()};

      expect(proposes, contains(t.minMensuel),
        reason: 'un « à partir de » qui ne correspond à aucune formule est '
                'exactement le défaut corrigé ici');
    });

    test('il suit le serveur quand les tarifs changent', () {
      final t = TarifsPremium.depuis({...complet,
        'premium_price_annual_fcfa': 24000});   // 2 000/mois
      expect(t.minMensuel, 2000);
    });

    test('le mois offert n\'entre pas dans le « à partir de »', () {
      // Une offre d'entrée qui ne se reconduit pas n'est pas un tarif. La
      // faire entrer dans le calcul annoncerait « à partir de 0 FCFA » et
      // décrirait mal ce que coûte réellement l'abonnement.
      final t = TarifsPremium.depuis(complet);

      expect(t.minMensuel, greaterThan(0));
      expect(t.minMensuel, t.mensuelDirect < (t.annuelDirect / 12).round()
          ? t.mensuelDirect
          : (t.annuelDirect / 12).round());
    });
  });

  group('l\'offre du parcours « code promo »', () {
    test('elle est lue chez le serveur', () {
      expect(TarifsPremium.depuis(complet).joursOffreCode, 30);
      expect(TarifsPremium.depuis({...complet, 'code_offer_days': 15})
          .joursOffreCode, 15);
    });

    test('le repli sert quand le serveur se tait', () {
      expect(TarifsPremium.depuis(null).joursOffreCode,
          TarifsPremium.joursOffreCodeDefaut);
    });

    test('le libellé se dit en mois quand c\'est un compte rond', () {
      String libelle(int j) =>
          TarifsPremium.depuis({...complet, 'code_offer_days': j})
              .libelleOffreCode;

      expect(libelle(30), '1 mois offert');
      expect(libelle(60), '2 mois offerts');
      // Et en jours sinon : « 0 mois offert » ou « 0,5 mois » ne se disent pas.
      expect(libelle(15), '15 jours offerts');
      expect(libelle(45), '45 jours offerts');
    });

    test('aucun tarif « code » ne subsiste dans la charge utile lue', () {
      // Le serveur ne les publie plus ; si un ancien serveur les renvoyait,
      // le modèle ne doit pas les ressusciter.
      final t = TarifsPremium.depuis({...complet,
        'premium_price_monthly_code_fcfa': 4200,
        'premium_price_annual_code_fcfa':  37800});

      expect(t.minMensuel, 4500, reason: 'les tarifs « code » sont ignorés');
      expect(t.prix(annuel: false), 6000);
    });
  });

  group('les moyens de paiement ne s\'inventent pas', () {
    test('une liste absente ne produit aucun numéro', () {
      final t = TarifsPremium.depuis({});
      expect(t.moyensPaiement, isEmpty);
      expect(t.paiementDisponible, isFalse,
        reason: 'le serveur qui ne publie rien ne doit pas être contredit par '
                'un numéro compilé dans le binaire');
    });

    test('une entrée sans téléphone est écartée', () {
      final t = TarifsPremium.depuis({'payment_methods': [
        {'key': 'orange_money', 'label': 'Orange Money', 'phone': ''},
        {'key': 'wave',         'label': 'Wave',         'phone': '22670000000'},
      ]});
      expect(t.moyensPaiement.length, 1);
      expect(t.moyensPaiement.first['label'], 'Wave');
    });

    test('les opérateurs annoncés sont ceux réellement publiés', () {
      expect(TarifsPremium.depuis(complet).libelleOperateurs,
          'Orange Money  ·  Wave');
    });

    test('aucun opérateur annoncé quand aucun n\'est publié', () {
      expect(TarifsPremium.depuis({}).libelleOperateurs, isEmpty);
    });
  });

  group('le serveur prime, le repli ne sert que d\'ultime recours', () {
    test('les valeurs du serveur sont retenues', () {
      final t = TarifsPremium.depuis(complet);
      expect(t.promoCode,   'CODE2030');
      expect(t.delaiDirect, '15 minutes ouvrables');
      expect(t.delaiCode,   '1 heure ouvrable');
      expect(t.plateformes, ['1xbet', 'melbet']);
    });

    test('une réponse vide retombe sur les replis chiffrés', () {
      final t = TarifsPremium.depuis(null);
      expect(t.mensuelDirect, TarifsPremium.mensuelDirectDefaut);
      expect(t.delaiDirect,   TarifsPremium.delaiDirectDefaut);
    });

    test('le code promo se passe de repli, deliberement', () {
      // Un tarif de repli est une approximation ; un code d'affiliation de
      // repli est un code qui ne credite personne. La constante valait
      // `PRONOWIN2025` alors que le code en service est `PRONOWIN2026` : hors
      // ligne, l'ecran affichait celui de l'an dernier, l'utilisateur le
      // recopiait chez le bookmaker, et son mois offert perdait sa
      // justification.
      final t = TarifsPremium.depuis(null);
      expect(t.promoCode, isEmpty);
      expect(t.offreCodeDisponible, isFalse);
    });

    test('une chaîne vide ou blanche ne fait pas un code', () {
      final t = TarifsPremium.depuis({'promo_code': '   ', 'review_delay_code': ''});
      expect(t.offreCodeDisponible, isFalse);
      expect(t.delaiCode, TarifsPremium.delaiCodeDefaut);
    });

    test('un code publié par le serveur est repris tel quel', () {
      final t = TarifsPremium.depuis({'promo_code': 'PRONOWIN2026'});
      expect(t.promoCode, 'PRONOWIN2026');
      expect(t.offreCodeDisponible, isTrue);
    });
  });

  group('le prix collecté suit la durée choisie', () {
    // Plus de dimension « méthode » : le parcours « code promo » ne facture
    // rien. Garder un paramètre `avecCode` aurait laissé croire à un tarif.
    final t = TarifsPremium.depuis(complet);
    test('mensuel', () => expect(t.prix(annuel: false), 6000));
    test('annuel',  () => expect(t.prix(annuel: true),  54000));
  });
}
