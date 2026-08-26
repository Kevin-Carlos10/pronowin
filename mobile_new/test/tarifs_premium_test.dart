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
    'premium_price_monthly_fcfa':      6000,
    'premium_price_annual_fcfa':       54000,
    'premium_price_monthly_code_fcfa': 4200,
    'premium_price_annual_code_fcfa':  37800,
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
      // 6000 · 4200 · 54000/12 = 4500 · 37800/12 = 3150
      expect(t.minMensuel, 3150);
      expect(t.minMensuelFormate, '3${fine}150');
    });

    test('le minimum correspond toujours à un tarif réellement proposé', () {
      final t = TarifsPremium.depuis(complet);
      final proposes = {
        t.mensuelDirect, t.mensuelCode,
        (t.annuelDirect / 12).round(), (t.annuelCode / 12).round(),
      };
      expect(proposes, contains(t.minMensuel),
        reason: 'un « à partir de » qui ne correspond à aucune formule est '
                'exactement le défaut corrigé ici');
    });

    test('il suit le serveur quand les tarifs changent', () {
      final t = TarifsPremium.depuis({...complet,
        'premium_price_annual_code_fcfa': 24000});   // 2 000/mois
      expect(t.minMensuel, 2000);
    });
  });

  group('la remise est calculée, jamais écrite', () {
    test('4 200 sur 6 000 donne 30 %', () {
      expect(TarifsPremium.depuis(complet).remisePourcent, 30);
    });

    test('elle suit un changement de tarif serveur', () {
      final t = TarifsPremium.depuis({...complet,
        'premium_price_monthly_code_fcfa': 3000});
      expect(t.remisePourcent, 50);
    });

    test('aucune remise négative si le code coûte plus cher', () {
      final t = TarifsPremium.depuis({...complet,
        'premium_price_monthly_code_fcfa': 9000});
      expect(t.remisePourcent, 0);
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

    test('une réponse vide retombe sur les replis', () {
      final t = TarifsPremium.depuis(null);
      expect(t.mensuelDirect, TarifsPremium.mensuelDirectDefaut);
      expect(t.promoCode,     TarifsPremium.promoCodeDefaut);
      expect(t.delaiDirect,   TarifsPremium.delaiDirectDefaut);
    });

    test('une chaîne vide ne remplace pas le repli', () {
      final t = TarifsPremium.depuis({'promo_code': '   ', 'review_delay_code': ''});
      expect(t.promoCode, TarifsPremium.promoCodeDefaut);
      expect(t.delaiCode, TarifsPremium.delaiCodeDefaut);
    });
  });

  group('le prix collecté suit la combinaison choisie', () {
    final t = TarifsPremium.depuis(complet);
    test('mensuel direct',  () => expect(t.prix(annuel: false, avecCode: false), 6000));
    test('annuel direct',   () => expect(t.prix(annuel: true,  avecCode: false), 54000));
    test('mensuel code',    () => expect(t.prix(annuel: false, avecCode: true),  4200));
    test('annuel code',     () => expect(t.prix(annuel: true,  avecCode: true),  37800));
  });
}
