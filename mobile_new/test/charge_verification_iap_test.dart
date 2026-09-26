import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/abonnement/data/iap_service.dart';

/// Ce qu'on envoie au backend après un achat, store par store.
///
/// Les deux stores n'envoient pas la même nature de valeur, et l'app faisait
/// comme si. `serverVerificationData` **est** le `purchaseToken` sur Android —
/// exactement ce que l'API Google attend. Sur iOS, le même champ porte le reçu
/// App Store encodé en base64 : l'API serveur d'Apple, elle, attend un
/// identifiant de transaction dans le chemin de
/// `/inApps/v1/subscriptions/{transactionId}`.
///
/// On envoyait donc le reçu entier à Apple. Réponse : 404, puis 404 en
/// sandbox, puis « Transaction introuvable ». Aucun achat iOS n'aurait abouti,
/// et l'acheteur était débité.
///
/// Le pendant de ce banc est `backend/src/__tests__/contrat_recu_apple.test.ts`,
/// qui vérifie que le serveur accepte bien ce qui est envoyé ici.
void main() {
  const jeton = 'jeton-google-abcdef123456';
  const recuApple = 'MIIT...reçu-App-Store-encodé-en-base64...==';
  const idTransaction = '2000000912345678';

  group('iOS envoie l\'identifiant de transaction', () {
    test('et non le reçu', () {
      final c = chargeDeVerification(
        estIOS: true,
        identifiantTransaction: idTransaction,
        donneeServeur: recuApple,
      );

      expect(c, isNotNull);
      expect(c!.store, 'apple');
      expect(c.receipt, idTransaction);
      expect(c.receipt, isNot(recuApple));
    });

    test('rien à envoyer sans identifiant', () {
      // Mieux vaut un échec nommé qu'un appel qui ne peut pas réussir.
      expect(
        chargeDeVerification(
          estIOS: true, identifiantTransaction: null, donneeServeur: recuApple),
        isNull,
      );
      expect(
        chargeDeVerification(
          estIOS: true, identifiantTransaction: '  ', donneeServeur: recuApple),
        isNull,
      );
    });
  });

  group('Android envoie le jeton d\'achat', () {
    test('qui est bien la donnée serveur', () {
      // Contrepartie : un correctif qui enverrait `purchaseID` des deux côtés
      // casserait Android, où c'est le jeton que Google attend.
      final c = chargeDeVerification(
        estIOS: false,
        identifiantTransaction: 'identifiant-ignoré-ici',
        donneeServeur: jeton,
      );

      expect(c, isNotNull);
      expect(c!.store, 'google');
      expect(c.receipt, jeton);
    });

    test('rien à envoyer sans jeton', () {
      expect(
        chargeDeVerification(
          estIOS: false, identifiantTransaction: idTransaction, donneeServeur: ''),
        isNull,
      );
    });
  });
}
