import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'aides/code_seul.dart';

/// Quand le catalogue du store ne se charge pas, l'écran doit pouvoir s'en
/// remettre.
///
/// Le paywall affichait : « Les achats ne sont pas disponibles sur cet appareil
/// pour le moment. Vérifie ta connexion et que ton compte store est bien
/// configuré. » Vérifier sa connexion ne servait à rien :
///
///   * `init()` commençait par `if (_ready) return true;` — et posait
///     `_ready = true` même quand `queryProductDetails` n'avait rien rendu.
///     Une fois passé par là, plus aucune tentative n'était possible ;
///   * `queryProductDetails` n'était pas protégé : une exception remontait
///     jusqu'au provider ;
///   * aucun bouton ne relançait quoi que ce soit.
///
/// L'utilisateur rétablissait donc sa connexion, revenait sur l'écran, et
/// lisait le même message — jusqu'à ce qu'il tue l'application. Un écran qui
/// demande une action dont il ne tient pas compte.
///
/// Ces vérifications sont textuelles : rien de tout cela n'est visible du
/// compilateur ni de l'analyseur, et l'écran s'affichait parfaitement.
void main() {
  late String service;
  late String page;

  setUpAll(() {
    String lire(String chemin) {
      final f = File(chemin);
      if (!f.existsSync()) fail('Fichier introuvable : $chemin');
      return f.readAsStringSync().pipeCodeSeul();
    }

    service = lire('lib/features/abonnement/data/iap_service.dart');
    page = lire(
        'lib/features/abonnement/presentation/pages/activer_premium_page.dart');
  });

  group('le service peut réessayer', () {
    test('« prêt » exige un catalogue non vide', () {
      // `_ready = true` inconditionnel était le cœur du défaut : l'écran se
      // croyait prêt sans rien à vendre.
      expect(service, contains('_ready = _products.isNotEmpty;'));
      expect(
        RegExp(r'_ready\s*=\s*true\s*;').hasMatch(service),
        isFalse,
        reason: '« prêt » ne doit plus être posé sans regarder le catalogue',
      );
    });

    test('le court-circuit d\'entrée regarde aussi le catalogue', () {
      // `if (_ready) return true;` interdisait toute nouvelle tentative.
      expect(service, contains('if (_ready && _products.isNotEmpty)'));
    });

    test('l\'interrogation du store est protégée', () {
      // Sans cela, un store injoignable faisait remonter l'exception jusqu'au
      // provider, et le catalogue gardait sa valeur précédente.
      final i = service.indexOf('queryProductDetails');
      expect(i, greaterThan(-1));
      final avant = service.substring(0, i);
      expect(avant.lastIndexOf('try {'),
          greaterThan(avant.lastIndexOf('_loadProducts')),
          reason: 'queryProductDetails doit être dans un try du chargement');
      expect(service, contains('_products = const [];'),
          reason: 'un échec doit laisser le catalogue vide, pas incertain');
    });

    test('l\'abonnement au flux n\'est pas repris à chaque tentative', () {
      // `init()` est désormais rappelable : réabonner à chaque appel
      // multiplierait les écoutes, donc les vérifications d'un même achat.
      expect(service, contains('_sub ??= _iap.purchaseStream.listen'));
    });
  });

  group('l\'écran propose une reprise', () {
    test('un bouton « Réessayer » existe', () {
      expect(page, contains("Key('iap-reessayer')"));
      expect(page, contains('Réessayer'));
    });

    test('il relance réellement le chargement', () {
      // Un bouton qui n'invaliderait pas le provider rendrait le même échec
      // instantanément — exactement ce qu'on reproche à l'ancien message.
      expect(page, contains('ref.invalidate(iapReadyProvider)'));
      expect(page, contains('onIapRetry'));
      expect(page, contains('onRetry:'));
    });

    test('la restauration reste joignable même sans catalogue', () {
      // Un achat déjà payé ne dépend pas du catalogue pour être rattrapé.
      expect(page, contains("Key('iap-restaurer-indisponible')"));
    });

    test('le message ne promet plus ce qu\'il ne fait pas', () {
      // « Vérifie ta connexion » sans moyen de réessayer désignait une action
      // sans effet.
      expect(page, contains('puis réessaie'));
      expect(
        page.contains('Vérifie ta connexion et que ton compte store est bien'),
        isFalse,
        reason: 'l\'ancien message renvoyait à une action sans effet',
      );
    });
  });
}
