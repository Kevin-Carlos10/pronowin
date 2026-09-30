import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:pronowin/firebase_options.dart';

/// L'envoi iOS vers App Store Connect : ce qu'Apple exige, et ce que le
/// workflow ne doit jamais faire.
///
/// Rien de tout cela ne se voit depuis Windows : le projet n'y compile pas
/// pour iOS. Une clé manquante se découvre au mieux après quarante minutes de
/// build sur Codemagic, au pire dans un courriel d'Apple — ou quand aucune
/// notification n'arrive sur les iPhone.
void main() {
  final racine = Directory.current.path.endsWith('mobile_new')
      ? Directory.current.parent
      : Directory.current;
  final ci = loadYaml(File('${racine.path}/codemagic.yaml').readAsStringSync()) as YamlMap;
  final envoi = (ci['workflows'] as YamlMap)['ios-app-store'] as YamlMap?;
  String lire(String chemin) => File(chemin).readAsStringSync();

  /// Une variable du workflow, écrite en clair dans son bloc `vars`.
  ///
  /// Pas d'héritage par la fusion YAML `<<` : rien ne prouvait que Codemagic
  /// l'applique, et une variable perdue ne se voyait qu'une fois le paquet
  /// construit. Une variable héritée est donc tenue pour absente.
  Object? variable(String nom) {
    final vars = (envoi!['environment'] as YamlMap)['vars'] as YamlMap;
    return vars[nom];
  }

  group('le workflow d\'envoi', () {
    test('existe, et ne part qu\'à la main', () {
      expect(envoi, isNotNull);
      // Chaque envoi consomme un numéro de build et arrive chez les testeurs :
      // pas à chaque push.
      expect(envoi!['triggering'], isNull);
    });

    test('les workflows automatiques ne partent que de main', () {
      // Lancés à chaque push de chaque branche, ils consommaient le quota de
      // minutes Mac à vérifier du travail en cours.
      for (final entree in (ci['workflows'] as YamlMap).entries) {
        final declenchement = (entree.value as YamlMap)['triggering'] as YamlMap?;
        if (declenchement == null) continue;
        final motifs = (declenchement['branch_patterns'] as YamlList?)
            ?.map((m) => (m as YamlMap)['pattern'])
            .toSet();
        expect(motifs, {'main'}, reason: '${entree.key} partirait de toutes les branches');
      }
    });

    test('construit le paquet du store : achat intégré, ni Mobile Money ni bookmakers', () {
      // La règle 3.1.1 d'Apple impose l'achat intégré pour un abonnement
      // numérique : un paquet du canal direct serait refusé, voire retiré.
      expect(variable('STORE_BUILD'), 'true');
      expect(variable('API_BASE_URL'), 'https://pronowin.space/api/v1');
    });

    test('signe pour l\'App Store, l\'identifiant de lot de l\'app créée', () {
      final signature = (envoi!['environment'] as YamlMap)['ios_signing'] as YamlMap;
      expect(signature['distribution_type'], 'app_store');
      expect(signature['bundle_identifier'], 'com.pronowin.app');
      expect(lire('ios/Runner.xcodeproj/project.pbxproj'),
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.pronowin.app;'));
    });

    test('connaît l\'identifiant Apple de l\'app, qui numérote les builds', () {
      expect('${variable('APP_STORE_APPLE_ID')}', matches(RegExp(r'^\d{9,12}$')));
    });

    test('envoie à TestFlight, jamais directement à l\'examen', () {
      final asc = (envoi!['publishing'] as YamlMap)['app_store_connect'] as YamlMap;
      expect(asc['submit_to_testflight'], isTrue);
      expect(asc['submit_to_app_store'], isFalse);
    });
  });

  group('ce qu\'Apple exige du paquet', () {
    test('la déclaration de chiffrement est faite', () {
      // Sans elle, chaque build reste bloqué dans TestFlight jusqu'à une
      // réponse manuelle dans App Store Connect.
      expect(lire('ios/Runner/Info.plist'),
          matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')));
    });

    test('les notifications push sont déclarées', () {
      // Retirées du temps du compte Apple gratuit : sans elles, Firebase
      // Messaging ne livre rien sur iPhone, et rien ne le signale.
      expect(lire('ios/Runner/Runner.entitlements'),
          matches(RegExp(r'<key>aps-environment</key>\s*<string>(development|production)</string>')));
    });

    test('Firebase désigne l\'app iOS de ce paquet, sinon Apple refuse chaque notification', () {
      // Les options désignaient `com.example.mobileNew`, l'app du modèle
      // Flutter d'origine : les jetons des iPhone étaient émis pour elle, et
      // chaque envoi revenait en « Invalid APNs credential ».
      final lot = ((envoi!['environment'] as YamlMap)['ios_signing'] as YamlMap)['bundle_identifier'] as String;
      expect(DefaultFirebaseOptions.ios.iosBundleId, lot);
      // Absent du dépôt : Codemagic l'écrit avant les vérifications.
      final plist = File('ios/Runner/GoogleService-Info.plist');
      if (plist.existsSync()) {
        final contenu = plist.readAsStringSync();
        expect(contenu, matches(RegExp('<key>BUNDLE_ID</key>\\s*<string>${RegExp.escape(lot)}</string>')));
        expect(contenu, matches(RegExp(
            '<key>GOOGLE_APP_ID</key>\\s*<string>${RegExp.escape(DefaultFirebaseOptions.ios.appId)}</string>')));
      }
    });

    test('« Se connecter avec Apple » est déclaré (règle 4.8)', () {
      expect(lire('ios/Runner/Runner.entitlements'),
          matches(RegExp(r'<key>com\.apple\.developer\.applesignin</key>\s*<array>\s*<string>Default</string>')));
    });

    test('iPhone seulement : l\'iPad imposerait les quatre orientations', () {
      // Build n° 3 refusé à l'envoi (erreur 90474) : l'app déclarait l'iPad
      // en portrait seul, alors que le multitâche de l'iPad exige les quatre
      // orientations. Elle est dessinée pour un téléphone en portrait.
      final projet = lire('ios/Runner.xcodeproj/project.pbxproj');
      final familles = RegExp(r'TARGETED_DEVICE_FAMILY = ([^;]+);')
          .allMatches(projet).map((m) => m.group(1)).toSet();
      expect(familles, {'1'});
      expect(lire('ios/Runner/Info.plist'), isNot(contains('UISupportedInterfaceOrientations~ipad')));
    });

    test('chaque accès sensible a sa description', () {
      // Une description manquante fait refuser l'envoi (ITMS-90683).
      final plist = lire('ios/Runner/Info.plist');
      for (final cle in ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription', 'NSFaceIDUsageDescription']) {
        expect(plist, matches(RegExp('<key>$cle</key>\\s*<string>[^<]{10,}</string>')), reason: cle);
      }
    });
  });
}
