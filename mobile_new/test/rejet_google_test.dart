import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/auth/data/datasources/google_auth_service.dart';

/// Le SDK Google renvoie le code `canceled` dans deux situations opposées :
/// l'utilisateur referme la fenêtre, et les services Google Play refusent le
/// compte. Traiter les deux comme une annulation laissait l'utilisateur devant
/// un bouton qui ne fait rien — le sélecteur s'ouvrait, se refermait, et aucun
/// message n'apparaissait.
///
/// Le cas observé en production :
///     [Google] code=canceled
///     [Google] description : [16] Account reauth failed.
void main() {
  group('séparer un refus système d\'une annulation', () {
    test('le cas observé est reconnu comme un refus', () {
      expect(estRejetSysteme('[16] Account reauth failed.'), isTrue);
    });

    test('tout code de statut entre crochets compte', () {
      // Le format `[nombre]` vient des services Google Play.
      for (final d in ['[4] Sign in required.', '[7] Network error.',
                       '  [10] Developer error.']) {
        expect(estRejetSysteme(d), isTrue, reason: d);
      }
    });

    test('une vraie annulation reste silencieuse', () {
      // Ces formes n'ont pas de code de statut : l'utilisateur a agi.
      for (final d in [null, '', 'activity is cancelled by the user.',
                       'User cancelled the flow']) {
        expect(estRejetSysteme(d), isFalse, reason: d ?? 'null');
      }
    });

    test('un crochet ailleurs dans le texte ne déclenche rien', () {
      // Le repère est ancré au début, sinon n'importe quelle phrase
      // contenant des crochets passerait pour un refus.
      expect(estRejetSysteme('cancelled [by user]'), isFalse);
    });
  });

  group('le message dit quoi faire', () {
    test('un problème de ré-authentification nomme la solution', () {
      final m = messageRejetSysteme('[16] Account reauth failed.');
      expect(m, contains('réglages'));
      expect(m, contains('Comptes'));
      // Et il propose toujours le chemin qui, lui, fonctionne.
      expect(m, contains('e-mail'));
    });

    test('un refus inconnu reste actionnable', () {
      final m = messageRejetSysteme('[42] Something unexpected.');
      expect(m, contains('e-mail'));
      expect(m, isNot(contains('[42]')),
          reason: 'le code de statut n\'a aucun sens pour l\'utilisateur');
    });

    test('aucun message ne laisse fuiter le texte technique', () {
      for (final d in ['[16] Account reauth failed.', '[7] Network error.', null]) {
        final m = messageRejetSysteme(d);
        expect(m, isNot(contains('Account reauth')));
        expect(m, isNot(contains('Google Play')));
      }
    });
  });
}
