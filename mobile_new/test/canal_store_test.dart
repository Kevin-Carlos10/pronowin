import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Ce qu'un build publié sur les stores n'a pas le droit de contenir.
///
/// `distribution_channel.dart` énumère ce que le canal gouverne : paiement
/// Mobile Money, tarif, **renvoi vers le bookmaker**, offre « code promo »,
/// chemin de mise à jour. C'était une promesse en commentaire — et l'une
/// d'elles n'était pas tenue.
///
/// La barre `BookmakerCotes` de l'onglet Cotes, un lien d'affiliation cliquable
/// vers un opérateur de paris, partait dans le paquet soumis à Google et Apple.
/// Seule la fenêtre de mise appliquait la règle.
///
/// Rien ne pouvait le voir : l'écran rendait parfaitement, l'analyseur ne
/// signalait rien, et le drapeau existait bel et bien — il n'était simplement
/// pas consulté à cet endroit. D'où ce garde-fou textuel : il porte sur la
/// structure du code, seule chose vérifiable sans exécuter les deux builds.
void main() {
  /// Surfaces qui exposent un opérateur de paris ou un paiement hors store,
  /// avec le fichier où elles sont montées.
  const surfaces = <String, ({String fichier, String motif})>{
    'barre d\'affiliation bookmaker': (
      fichier: 'lib/features/pronostics/presentation/pages/match_detail_page.dart',
      motif:   'BookmakerCotes(',
    ),
    // Le motif vise le **point de montage**, pas une mention : la fonction
    // utilitaire qui construit le lien vit plus haut dans le fichier et n'a
    // rien a etre conditionnee.
    'renvoi bookmaker depuis la mise': (
      fichier: 'lib/features/bankroll/presentation/widgets/miser_dialog.dart',
      motif:   'onTap: _launch1xBet',
    ),
  };

  String lire(String chemin) {
    final f = File(chemin);
    if (!f.existsSync()) fail('Fichier introuvable : $chemin');
    return f.readAsStringSync();
  }

  group('le canal store masque les surfaces de jeu d\'argent', () {
    for (final e in surfaces.entries) {
      test('${e.key} est conditionnée au canal', () {
        final source = lire(e.value.fichier);
        final index  = source.indexOf(e.value.motif);
        expect(index, greaterThan(-1),
          reason: 'motif « ${e.value.motif} » absent : le test ne prouve plus rien');

        // Le garde doit précéder le montage, à portée raisonnable — un
        // `if (!isStoreBuild)` posé 400 lignes plus haut ne gouverne pas ce
        // widget-ci.
        final avant = source.substring(
          index > 600 ? index - 600 : 0, index);
        expect(avant.contains('isStoreBuildProvider'), isTrue,
          reason: '${e.key} : montée sans consulter le canal de distribution. '
                  'Elle partirait dans le paquet soumis aux stores.');
      });
    }
  });

  group('le paiement hors store reste hors du paquet publié', () {
    final paywall = lire(
      'lib/features/abonnement/presentation/pages/activer_premium_page.dart');

    test('le formulaire Mobile Money n\'est atteignable qu\'en canal direct', () {
      // `_goToForm` est le seul chemin vers les onglets de paiement. Son
      // déclencheur doit vivre dans la branche non-store.
      final cta = paywall.indexOf('_PaywallCTA(');
      expect(cta, greaterThan(-1));
      final iap = paywall.indexOf('if (iapMode)');
      expect(iap, greaterThan(-1),
        reason: 'la bascule achat intégré / Mobile Money a disparu');
      expect(iap, lessThan(cta),
        reason: 'le bouton qui mène au formulaire doit être dans la branche '
                'non-store, après la bascule');
    });

    test('la FAQ Mobile Money ne s\'affiche pas en achat intégré', () {
      expect(paywall.contains('iapMode'), isTrue);
      // Apple 3.1.1 interdit de mentionner un moyen de paiement externe.
      final faq = paywall.indexOf('class _PaywallFaq');
      expect(faq, greaterThan(-1));
      expect(paywall.substring(faq, faq + 900).contains('iapMode'), isTrue,
        reason: 'la FAQ doit connaître le canal : elle décrit sinon un '
                'paiement Mobile Money dans une application publiée');
    });
  });

  test('le défaut du canal penche du côté store', () {
    final canal = lire('lib/core/config/distribution_channel.dart');
    // Un drapeau oublié doit produire un build « store » — cassé et visible —
    // plutôt qu'un build « direct » envoyé sur Play, qui serait un motif de
    // retrait d'application.
    // La règle réelle : **seul un « false » explicite ouvre le canal direct**.
    // Valeur absente, vide ou mal orthographiée retombent sur « store ».
    expect(
      RegExp(r"_drapeau\s*==\s*'false'\s*\?\s*CanalDistribution\.direct")
          .hasMatch(canal),
      isTrue,
      reason: 'seul un « false » explicite doit ouvrir le canal direct : un '
              'drapeau oublié produit alors un build store — cassé et visible '
              '— jamais un APK d\'affiliation envoyé sur Play',
    );
    // iOS n'a pas de canal direct : pas de chargement latéral.
    expect(canal.contains('Platform.isIOS'), isTrue);
  });
}
