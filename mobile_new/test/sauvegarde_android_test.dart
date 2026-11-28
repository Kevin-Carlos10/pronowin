import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/constants/app_constants.dart';

/// Ce que la sauvegarde automatique d'Android a le droit d'emporter.
///
/// Android sauvegarde par défaut — `allowBackup` vaut `true` quand rien n'est
/// déclaré. Le stock de `flutter_secure_storage` partait donc sur Google Drive
/// avec les jetons de session et le code PIN. Sa clé de chiffrement, elle, vit
/// dans le Keystore de l'appareil et n'est jamais sauvegardée : restaurés
/// ailleurs, ces octets sont illisibles.
///
/// Le greffon encaisse le cas — `resetOnError` vaut `true` par défaut en
/// v10.2.0, il efface le stock plutôt que de lever une exception. Il ne s'agit
/// donc pas d'un plantage à réparer, mais d'un export d'identifiants de compte
/// vers un service tiers, qui ne sert à personne : ni à l'utilisateur, qui ne
/// pourra jamais s'en resservir, ni à nous.
///
/// Le reste continue d'être sauvegardé. C'est ce qui rend un changement de
/// téléphone agréable, et rien là-dedans n'identifie personne.
void main() {
  final manifeste = File('android/app/src/main/AndroidManifest.xml');
  final xml       = 'android/app/src/main/res/xml';

  /// Nom du fichier de préférences de `flutter_secure_storage` sur Android
  /// (`DEFAULT_PREF_NAME` dans `FlutterSecureStorageConfig.java`).
  const stock = 'FlutterSecureStorage.xml';

  group('sauvegarde automatique Android', () {
    test('les deux jeux de règles existent', () {
      // Android 12 a introduit `dataExtractionRules` sans retirer
      // `fullBackupContent` : n'en fournir qu'un laisse une moitié du parc
      // sauvegarder ce qu'on voulait exclure.
      expect(File('$xml/backup_rules.xml').existsSync(), isTrue,
        reason: 'règles Android 11 et antérieur');
      expect(File('$xml/data_extraction_rules.xml').existsSync(), isTrue,
        reason: 'règles Android 12 et suivants');
    });

    test('le stock sécurisé est exclu des deux côtés', () {
      final ancien = File('$xml/backup_rules.xml').readAsStringSync();
      expect(ancien, contains('domain="sharedpref"'));
      expect(ancien, contains('path="$stock"'));

      final recent = File('$xml/data_extraction_rules.xml').readAsStringSync();
      // Android 12 sépare la sauvegarde distante du transfert d'appareil à
      // appareil. N'en couvrir qu'un laisse le stock partir par l'autre.
      for (final section in const ['cloud-backup', 'device-transfer']) {
        final debut = recent.indexOf('<$section>');
        expect(debut, greaterThan(-1), reason: '<$section> manquante');
        final fin = recent.indexOf('</$section>', debut);
        expect(fin, greaterThan(debut));

        final corps = recent.substring(debut, fin);
        expect(corps, contains('path="$stock"'),
          reason: 'le stock sécurisé n\'est pas exclu de <$section>');
      }
    });

    test('le manifeste désigne les deux fichiers', () {
      // Les fichiers peuvent exister sans être référencés : Android les
      // ignorerait alors en silence et sauvegarderait tout.
      final src = manifeste.readAsStringSync();

      expect(src, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(src, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    });
  });

  group('clés de stockage — une seule source', () {
    test('aucune clé n\'est écrite en clair dans un appel au stock', () {
      // Distinction qui compte : `data['access_token']` lit un champ de la
      // réponse JSON du serveur — un autre espace de noms, qui doit suivre le
      // backend et non nos constantes. Seule une clé passée à `read`, `write`,
      // `delete` ou `containsKey` est concernée.
      final motif = RegExp(
        r"\b(read|write|delete|containsKey)\(\s*(?:key:\s*)?'"
        '(${AppConstants.accessTokenKey}|${AppConstants.refreshTokenKey}'
        '|${AppConstants.userKey})'
        r"'");

      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)
          .whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('app_constants.dart')) continue;

        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (motif.hasMatch(lignes[i])) {
            fautifs.add('${f.path.replaceAll(r'\', '/')}:${i + 1}');
          }
        }
      }

      expect(fautifs, isEmpty,
        reason: 'clé recopiée au lieu d\'être lue dans AppConstants :\n'
                '${fautifs.join('\n')}');
    });
  });
}
