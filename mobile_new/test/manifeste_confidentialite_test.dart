import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Le manifeste de confidentialité iOS, et sa présence dans le bundle.
///
/// Depuis mai 2024, App Store Connect refuse à l'envoi (`ITMS-91053`) toute
/// application qui touche une « required reason API » sans manifeste. Le
/// projet n'en avait aucun : l'envoi aurait échoué au premier essai, après le
/// build, sans que rien dans le dépôt ne le laisse prévoir.
///
/// Deux choses distinctes, et c'est la seconde qui se perd :
///  - le fichier existe et déclare ce que l'application collecte ;
///  - il est **membre du projet Xcode**, donc copié dans le bundle. Un
///    `.xcprivacy` posé à côté du projet sans y être référencé ne part pas
///    avec l'application, et l'envoi échoue exactement comme s'il n'existait
///    pas.
///
/// Ce que ce test ne vérifie pas : que les déclarations soient **exactes**.
/// Aucun test ne peut le faire — c'est une déclaration légale, elle engage
/// l'éditeur, et elle doit être relue à chaque fois qu'un écran se met à
/// collecter autre chose.
void main() {
  final manifeste = File('ios/Runner/PrivacyInfo.xcprivacy');
  final pbxproj   = File('ios/Runner.xcodeproj/project.pbxproj');

  group('manifeste de confidentialité iOS', () {
    test('le fichier existe', () {
      expect(manifeste.existsSync(), isTrue,
        reason: 'ios/Runner/PrivacyInfo.xcprivacy est requis à l\'envoi');
    });

    test('les quatre clés attendues par Apple sont présentes', () {
      final src = manifeste.readAsStringSync();

      for (final cle in const [
        'NSPrivacyTracking',
        'NSPrivacyTrackingDomains',
        'NSPrivacyAccessedAPITypes',
        'NSPrivacyCollectedDataTypes',
      ]) {
        expect(src, contains('<key>$cle</key>'), reason: '$cle manquante');
      }
    });

    test('chaque type de donnée déclare son usage et son rattachement', () {
      final src = manifeste.readAsStringSync();

      // Un type déclaré sans `Purposes` fait rejeter le manifeste entier.
      final types  = RegExp(r'<string>NSPrivacyCollectedDataType[A-Z]\w*</string>')
          .allMatches(src).length;
      final usages = RegExp(r'<string>NSPrivacyCollectedDataTypePurpose\w+</string>')
          .allMatches(src).length;
      final liens  = RegExp(r'<key>NSPrivacyCollectedDataTypeLinked</key>')
          .allMatches(src).length;

      // `types` compte aussi les usages : ils commencent par le même préfixe.
      final vraisTypes = types - usages;

      expect(vraisTypes, greaterThanOrEqualTo(5),
        reason: 'ANALYSEUR DÉFAILLANT ou manifeste quasi vide : $vraisTypes types');
      expect(usages, greaterThanOrEqualTo(vraisTypes),
        reason: 'un type de donnée sans usage déclaré fait rejeter le manifeste');
      expect(liens, vraisTypes,
        reason: 'chaque type doit dire s\'il est rattaché à l\'utilisateur');
    });

    test('le manifeste est membre du projet Xcode', () {
      // Les quatre endroits où Xcode inscrit une ressource. En oublier un seul
      // suffit à ce que le fichier ne parte pas dans le bundle.
      final src = pbxproj.readAsStringSync();

      final ref = RegExp(
        r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference')
          .firstMatch(src);
      expect(ref, isNotNull, reason: 'aucune PBXFileReference');

      final build = RegExp(
        r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy in Resources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})')
          .firstMatch(src);
      expect(build, isNotNull, reason: 'aucun PBXBuildFile');
      expect(build!.group(2), ref!.group(1),
        reason: 'le PBXBuildFile pointe sur une autre référence');

      // Présence dans le groupe Runner, et dans la phase Resources.
      expect(src, contains('${ref.group(1)} /* PrivacyInfo.xcprivacy */,'),
        reason: 'absent des enfants du groupe Runner');
      expect(src, contains('${build.group(1)} /* PrivacyInfo.xcprivacy in Resources */,'),
        reason: 'absent de la phase Copy Bundle Resources');
    });

    test('le projet Xcode n\'a pas été déséquilibré', () {
      // Un pbxproj mal formé casse toute compilation iOS, et cette machine ne
      // peut pas la lancer. Le contrôle est faible mais il attrape la faute la
      // plus probable d'une édition à la main.
      final src = pbxproj.readAsStringSync();

      expect('{'.allMatches(src).length, '}'.allMatches(src).length);
      expect('('.allMatches(src).length, ')'.allMatches(src).length);

      // Aucun identifiant Xcode ne doit être défini deux fois.
      // Dart n'accepte pas les drapeaux en ligne `(?m)` : ils passent par le
      // constructeur.
      final defs = RegExp(r'^\t\t([0-9A-F]{24}) /\*', multiLine: true)
          .allMatches(src).map((m) => m.group(1)!).toList();
      expect(defs.length, greaterThanOrEqualTo(30),
        reason: 'ANALYSEUR DÉFAILLANT : ${defs.length} identifiants lus');
      expect(defs.toSet().length, defs.length,
        reason: 'identifiant défini deux fois');
    });
  });
}
