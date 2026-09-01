import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/storage/secure_storage.dart';
import 'package:pronowin/features/parametres/data/pin_store.dart';
import 'package:pronowin/features/parametres/presentation/providers/security_provider.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage chiffré simulé : le vrai passe par le Keystore Android / la
/// Keychain iOS, indisponibles hors appareil. Ce double garde la même
/// interface, ce qui suffit à valider la logique de `PinStore`.
class _SecureFactice implements SecureStorageService {
  final Map<String, String> valeurs = {};

  @override
  Future<void> write(String key, String value) async => valeurs[key] = value;
  @override
  Future<String?> read(String key) async => valeurs[key];
  @override
  Future<void> delete(String key) async => valeurs.remove(key);
  @override
  Future<void> deleteAll() async => valeurs.clear();
  @override
  Future<bool> containsKey(String key) async => valeurs.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SecureFactice secure;
  late PinStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = _SecureFactice();
    store  = PinStore(secure);
  });

  group('PinStore — le code ne doit jamais être lisible', () {
    test('le code enregistré n\'apparaît nulle part en clair', () async {
      await store.save('4271');

      expect(secure.valeurs.values.join('|').contains('4271'), isFalse,
          reason: 'le PIN lui-même ne doit pas être stocké');
      expect(await store.verify('4271'), isTrue);
      expect(await store.verify('4272'), isFalse);
    });

    test('deux installations avec le même code donnent des empreintes différentes',
        () async {
      await store.save('0000');

      final secondSecure = _SecureFactice();
      await PinStore(secondSecure).save('0000');

      // Sans sel, une table pré-calculée de 10 000 entrées suffirait à
      // retrouver n'importe quel PIN à 4 chiffres depuis son empreinte.
      expect(secure.valeurs['pin_hash'], isNotNull);
      expect(secure.valeurs['pin_hash'],
          isNot(equals(secondSecure.valeurs['pin_hash'])));
      expect(secure.valeurs['pin_salt'],
          isNot(equals(secondSecure.valeurs['pin_salt'])));
    });

    test('un nouveau code remplace l\'ancien', () async {
      await store.save('1111');
      await store.save('2222');

      expect(await store.verify('1111'), isFalse);
      expect(await store.verify('2222'), isTrue);
    });

    test('clear() efface tout', () async {
      await store.save('1234');
      await store.clear();

      expect(await store.hasPin(), isFalse);
      expect(await store.verify('1234'), isFalse);
      expect(secure.valeurs, isEmpty);
    });

    test('sans code défini, aucune saisie ne passe', () async {
      expect(await store.hasPin(), isFalse);
      expect(await store.verify(''), isFalse);
      expect(await store.verify('0000'), isFalse);
    });
  });

  group('PinStore — migration depuis l\'ancien stockage en clair', () {
    test('un code hérité reste valable après mise à jour', () async {
      // L'état d'un utilisateur qui avait déjà un PIN avant ce correctif.
      SharedPreferences.setMockInitialValues({'pin_code': '9876'});

      expect(await store.hasPin(), isTrue,
          reason: 'sans migration, la mise à jour déverrouillerait le compte');
      expect(await store.verify('9876'), isTrue);
      expect(await store.verify('1234'), isFalse);
    });

    test('l\'ancienne valeur en clair est supprimée après migration', () async {
      SharedPreferences.setMockInitialValues({'pin_code': '9876'});
      await store.hasPin();

      final p = await SharedPreferences.getInstance();
      expect(p.getString('pin_code'), isNull,
          reason: 'la copie en clair ne doit pas survivre à la migration');
      expect(secure.valeurs.values.join('|').contains('9876'), isFalse);
    });

    test('migrer deux fois ne casse rien', () async {
      SharedPreferences.setMockInitialValues({'pin_code': '5555'});
      await store.hasPin();
      await store.hasPin();

      expect(await store.verify('5555'), isTrue);
    });

    test('une valeur héritée vide n\'invente pas de code', () async {
      SharedPreferences.setMockInitialValues({'pin_code': ''});

      expect(await store.hasPin(), isFalse);
    });
  });

  group('doitVerrouiller — une seule décision, partagée', () {
    test('aucun verrou configuré : pas d\'écran de verrouillage', () async {
      expect(
        await doitVerrouiller(
          settings: const AppSettings(pinEnabled: false, bioEnabled: false),
          pinStore: store),
        isFalse);
    });

    test('PIN activé mais aucun code défini : pas de verrou', () async {
      // Le cas piège : afficher l'écran sans code enregistré enfermerait
      // l'utilisateur devant un clavier qu'aucune saisie ne peut satisfaire.
      expect(
        await doitVerrouiller(
          settings: const AppSettings(pinEnabled: true, bioEnabled: false),
          pinStore: store),
        isFalse);
    });

    test('PIN activé et code défini : verrou', () async {
      await store.save('1234');
      expect(
        await doitVerrouiller(
          settings: const AppSettings(pinEnabled: true, bioEnabled: false),
          pinStore: store),
        isTrue);
    });

    test('biométrie seule suffit à verrouiller', () async {
      expect(
        await doitVerrouiller(
          settings: const AppSettings(pinEnabled: false, bioEnabled: true),
          pinStore: store),
        isTrue);
    });

    test('un code hérité déclenche encore le verrou', () async {
      SharedPreferences.setMockInitialValues({'pin_code': '4444'});
      expect(
        await doitVerrouiller(
          settings: const AppSettings(pinEnabled: true, bioEnabled: false),
          pinStore: store),
        isTrue);
    });
  });

  group('messageErreurBio — jamais de PlatformException brute à l\'écran', () {
    test('chaque code connu donne une phrase en français', () {
      for (final code in const [
        'NotAvailable', 'NotEnrolled', 'PasscodeNotSet',
        'LockedOut', 'PermanentlyLockedOut', 'no_fragment_activity',
      ]) {
        final msg = messageErreurBio(PlatformException(code: code));
        expect(msg, isNot(contains('PlatformException')));
        expect(msg, isNot(contains(code)));
        expect(msg.trim(), isNotEmpty);
      }
    });

    test('chaque code connu produit un texte distinct', () {
      // Un switch qui retomberait par erreur sur `default` passerait les
      // contrôles ci-dessus sans que personne s'en aperçoive.
      final textes = const [
        'NotAvailable', 'NotEnrolled', 'PasscodeNotSet',
        'LockedOut', 'PermanentlyLockedOut', 'no_fragment_activity',
      ].map((c) => messageErreurBio(PlatformException(code: c))).toSet();

      expect(textes.length, 6);
      expect(textes.contains(messageErreurBio(Exception('inconnu'))), isFalse,
          reason: 'aucun cas connu ne doit retomber sur le message générique');
    });

    test('un échec inconnu reste intelligible', () {
      final msg = messageErreurBio(Exception('quelque chose d\'inattendu'));
      expect(msg, isNot(contains('Exception')));
      expect(msg, contains('code PIN'));
    });
  });
}
