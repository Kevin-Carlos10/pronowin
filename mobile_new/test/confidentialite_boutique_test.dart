import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/parametres/presentation/pages/legal_page.dart';
import 'package:pronowin/l10n/app_strings.dart';

/// La politique de confidentialité nomme la boutique qui encaisse vraiment.
///
/// Le canal store disait « Les informations de paiement sont gérées par
/// Google Play » — y compris sur iPhone, où l'abonnement passe par l'achat
/// intégré d'Apple. Un examinateur de l'App Store qui lit la politique y
/// trouvait la boutique d'un autre système.
///
/// Les contrôles appellent `sectionsLegales` et lisent ce qu'elle rend, pas le
/// texte source : un commentaire qui cite Google Play ne doit ni faire échouer
/// ces tests, ni les faire passer.
void main() {
  String texte(LegalType type, {required bool estStore, required bool estIOS}) =>
      sectionsLegales(type, estStore: estStore, estIOS: estIOS)
          .map((s) => '${s.title}\n${s.content}')
          .join('\n');

  tearDown(() => AppStrings.setCurrentLanguage('fr'));

  for (final langue in ['fr', 'en']) {
    test('$langue — sur iPhone, aucun texte légal ne nomme Google Play', () {
      AppStrings.setCurrentLanguage(langue);
      for (final type in LegalType.values) {
        final t = texte(type, estStore: true, estIOS: true);
        expect(t, isNotEmpty,
            reason: '$type ne rend aucun texte : le test ne prouve plus rien');
        expect(t.toLowerCase(), isNot(contains('google play')),
            reason: '$type nomme Google Play dans la version iPhone, où '
                    'l\'abonnement est facturé par Apple');
      }

      // Et la clause n'a pas simplement disparu : elle nomme Apple.
      expect(texte(LegalType.confidentialite, estStore: true, estIOS: true),
          contains('App Store'),
          reason: 'la version iPhone doit dire qui gère le paiement');
    });

    test('$langue — sur Android, le canal store nomme toujours Google Play', () {
      AppStrings.setCurrentLanguage(langue);
      final t = texte(LegalType.confidentialite, estStore: true, estIOS: false);
      expect(t, contains('Google Play'),
          reason: 'sur Android, c\'est Google Play qui facture');
      expect(t, isNot(contains('App Store')),
          reason: 'la version Android ne doit pas renvoyer à la boutique '
                  'd\'Apple');
    });
  }

  test('les trois versions déclarent la connexion Apple, la mesure d\'audience '
       'et le rattachement des plantages au compte', () {
    // Ces trois déclarations ne dépendent ni du canal ni du système : la
    // connexion avec Apple ou Google, Firebase Analytics et Crashlytics sont
    // les mêmes partout.
    const attendus = [
      'Se connecter avec Apple',
      'adresse relais',
      'si vous acceptez de le partager',
      'Firebase Analytics',
      "Mesure d'audience",
      'Ni nom, ni adresse e-mail, ni numéro de téléphone, ni montant',
      "associés à l'identifiant de votre compte",
    ];
    for (final (estStore, estIOS) in [(true, true), (true, false), (false, false)]) {
      final t = texte(LegalType.confidentialite, estStore: estStore, estIOS: estIOS);
      for (final mot in attendus) {
        expect(t, contains(mot),
            reason: 'canal ${estStore ? 'store' : 'direct'}, '
                    '${estIOS ? 'iPhone' : 'Android'} : « $mot » manque');
      }
    }
  });

  test('chaque section de la politique a sa traduction anglaise', () {
    // `trCurrent` retombe sur le français quand une clé manque : sans ce
    // contrôle, une phrase modifiée d'un côté seulement s'afficherait en
    // français à un utilisateur anglophone, sans que rien n'échoue.
    for (final (estStore, estIOS) in [(true, true), (true, false), (false, false)]) {
      final fr = sectionsLegales(LegalType.confidentialite,
          estStore: estStore, estIOS: estIOS);
      AppStrings.setCurrentLanguage('en');
      final en = sectionsLegales(LegalType.confidentialite,
          estStore: estStore, estIOS: estIOS);
      AppStrings.setCurrentLanguage('fr');

      for (var i = 0; i < fr.length; i++) {
        expect(en[i].content, isNot(fr[i].content),
            reason: '« ${fr[i].title} » n\'a pas de traduction anglaise');
      }
    }
  });

  testWidgets('la page ouverte sur iPhone ne nomme pas Google Play', (tester) async {
    // La fonction reçoit le système ; c'est la page qui le lui donne. Ce
    // contrôle vérifie ce branchement.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LegalPage(type: LegalType.confidentialite))));
    await tester.pumpAndSettle();

    final affiche = tester
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((t) => t.data ?? '')
        .join('\n');
    debugDefaultTargetPlatformOverride = null;

    expect(affiche, contains('Données collectées'),
        reason: 'la section n\'est pas construite : le test ne prouve rien');
    expect(affiche, isNot(contains('Google Play')));
    expect(affiche, contains("gérées par Apple, via l'App Store"));
  });
}
