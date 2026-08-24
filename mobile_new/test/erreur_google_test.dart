import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pronowin/features/auth/data/datasources/google_auth_service.dart';

/// L'échec d'une connexion Google ne laissait dans logcat qu'un
/// « GetCredentialResponse error returned from framework » émis par Android —
/// qui ne dit ni quel code Google a renvoyé, ni pourquoi. À l'écran,
/// l'utilisateur recevait le `toString()` d'une exception.
///
/// Trois des sept codes ne sont pas des incidents d'usage mais des défauts de
/// configuration : ils ne se résolvent pas en réessayant. Le message doit le
/// dire, sinon l'utilisateur s'acharne et le support enquête à l'aveugle.
void main() {
  GoogleSignInException ex(GoogleSignInExceptionCode code) =>
      GoogleSignInException(code: code);

  group('chaque code produit un message utile', () {
    test('aucun message ne laisse fuiter le nom de l\'exception', () {
      for (final code in GoogleSignInExceptionCode.values) {
        final m = messageErreurGoogle(ex(code));
        expect(m, isNot(contains('GoogleSignIn')));
        expect(m, isNot(contains('Exception')));
        expect(m.trim(), isNotEmpty);
      }
    });

    test('les sept codes ont chacun leur texte', () {
      // Un `switch` qui retomberait par erreur sur une branche commune
      // passerait le contrôle précédent sans que personne s'en aperçoive.
      final textes = GoogleSignInExceptionCode.values
          .map((c) => messageErreurGoogle(ex(c)))
          .toSet();
      expect(textes.length, GoogleSignInExceptionCode.values.length);
    });
  });

  group('un défaut de configuration se distingue d\'un incident', () {
    test('une erreur de configuration propose le repli e-mail', () {
      // Réessayer ne servira à rien : autant orienter vers le chemin qui, lui,
      // fonctionne.
      for (final code in [
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.unknownError,
      ]) {
        expect(messageErreurGoogle(ex(code)), contains('e-mail'),
            reason: '$code doit renvoyer vers le chemin qui marche');
      }
    });

    test('une interruption invite au contraire à réessayer', () {
      final m = messageErreurGoogle(ex(GoogleSignInExceptionCode.interrupted));
      expect(m, contains('Réessaie'));
      expect(m, isNot(contains('e-mail')));
    });

    test('une annulation ne dramatise pas', () {
      // L'utilisateur a fermé le sélecteur : ce n'est pas un échec, et le
      // message ne doit ni s'excuser ni proposer une solution de repli.
      final m = messageErreurGoogle(ex(GoogleSignInExceptionCode.canceled));
      expect(m, 'Connexion annulée.');
    });
  });
}
