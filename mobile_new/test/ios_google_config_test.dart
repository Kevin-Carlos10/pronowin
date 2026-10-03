import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Cohérence de la configuration Google côté iOS.
///
/// Trois fichiers doivent s'accorder, et rien ne le vérifie au build :
/// `GoogleService-Info.plist` (fourni par Firebase), `Info.plist` (le schéma de
/// retour), et `google-services.json` (le versant Android du même projet).
///
/// Quand ils divergent, rien n'échoue à la compilation. L'utilisateur choisit
/// son compte Google, Safari s'ouvre… et ne rend jamais la main. Le message
/// d'erreur, s'il y en a un, ne mentionne aucun de ces fichiers.
///
/// Ces contrôles tournent sous Windows comme ailleurs — c'est justement leur
/// intérêt : le projet ne peut pas être compilé pour iOS depuis un PC, donc
/// c'est la seule vérification possible avant de passer sur un Mac.
void main() {
  const racineIos = 'ios/Runner';
  final plistGoogle = File('$racineIos/GoogleService-Info.plist');
  final plistApp    = File('$racineIos/Info.plist');
  final jsonAndroid = File('android/app/google-services.json');

  String? valeurPlist(String contenu, String cle) {
    final m = RegExp('<key>$cle</key>\\s*<string>([^<]*)</string>').firstMatch(contenu);
    return m?.group(1);
  }

  group('GoogleService-Info.plist', () {
    test('le fichier existe et n\'est plus le gabarit', () {
      expect(plistGoogle.existsSync(), isTrue,
          reason: 'télécharger depuis la console Firebase');
      final src = plistGoogle.readAsStringSync();
      expect(src, isNot(contains('TODO_REMPLACER')),
          reason: 'le gabarit livré avec le projet est encore en place');
    });

    test('le bundle correspond à celui que Xcode construit', () {
      // Firebase ne permet pas de renommer un bundle : une app créée avec le
      // mauvais identifiant doit être refaite, et le fichier retéléchargé.
      final src = plistGoogle.readAsStringSync();
      expect(valeurPlist(src, 'BUNDLE_ID'), 'com.pronowin.app');
    });

    test('toutes les clés nécessaires sont renseignées', () {
      final src = plistGoogle.readAsStringSync();
      for (final cle in ['CLIENT_ID', 'REVERSED_CLIENT_ID', 'API_KEY',
                         'PROJECT_ID', 'GOOGLE_APP_ID']) {
        final v = valeurPlist(src, cle);
        expect(v, isNotNull, reason: '$cle absente');
        expect(v, isNotEmpty, reason: '$cle vide');
      }
    });
  });

  group('Info.plist — le schéma de retour', () {
    test('le REVERSED_CLIENT_ID figure dans les URL schemes', () {
      // Sans lui, le SDK Google ouvre Safari et l'app ne reprend jamais la
      // main. Rien ne plante : l'utilisateur reste simplement bloqué.
      final attendu = valeurPlist(
          plistGoogle.readAsStringSync(), 'REVERSED_CLIENT_ID')!;
      expect(plistApp.readAsStringSync(), contains(attendu),
          reason: 'ajouter « $attendu » à CFBundleURLSchemes');
    });

    test('le schéma des deep links reste présent', () {
      // La connexion Google ne doit pas se faire au prix des liens profonds.
      expect(plistApp.readAsStringSync(), contains('<string>pronowin</string>'));
    });
  });

  group('cohérence entre iOS et Android', () {
    test('les deux plateformes visent le même projet Firebase', () {
      final ios = plistGoogle.readAsStringSync();
      expect(valeurPlist(ios, 'PROJECT_ID'), 'pronowin-f7653');
      expect(jsonAndroid.readAsStringSync(), contains('pronowin-f7653'));
    });

    test('le client Android cité par le plist iOS est bien le nôtre', () {
      // Le plist iOS recopie l'identifiant Android. S'ils divergent, c'est que
      // l'un des deux fichiers vient d'une application Firebase différente —
      // exactement l'erreur rencontrée avec l'app `com.example.mobile_new`.
      final vuDIos = valeurPlist(
          plistGoogle.readAsStringSync(), 'ANDROID_CLIENT_ID');
      expect(vuDIos, isNotNull);
      expect(jsonAndroid.readAsStringSync(), contains(vuDIos!),
          reason: 'les deux fichiers ne décrivent pas la même application');
    });
  });
}
