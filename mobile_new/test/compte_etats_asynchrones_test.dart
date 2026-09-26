import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'aides/code_seul.dart';

/// Absence, chargement et panne ne se ressemblent pas.
///
/// ── Le rafraîchissement rendait la main trop tôt ──────────────────────────
///
/// `rafraichirDonneesCompte` appelait `invalidate` sur six providers, ce qui
/// les marque périmés et rend la main aussitôt. L'indicateur du geste
/// « tirer pour rafraîchir » s'arrêtait donc avant qu'une seule réponse ne
/// soit revenue : le geste paraissait n'avoir servi à rien, puis l'écran
/// changeait tout seul une seconde plus tard.
///
/// ── Et l'onglet Parrainage inventait des données ──────────────────────────
///
/// `valueOrNull ?? {}` faisait retomber chaque champ sur sa valeur par défaut.
/// Pendant un chargement ou après une panne, l'écran affichait un barème
/// complet — 500 F, 200 F, seuil à 2 000 — avec « 0 filleul » et « 0 FCFA de
/// gains », comme si le serveur l'avait dit. Un parrain qui a dix filleuls
/// voyait son compte à zéro, sans un mot.
///
/// Contrôles textuels : ni le compilateur ni l'analyseur ne voient un écran
/// qui affiche des valeurs par défaut à la place d'un état.
void main() {
  late String page;

  setUpAll(() {
    final f = File('lib/features/compte/presentation/pages/compte_page.dart');
    if (!f.existsSync()) fail('Page introuvable : ${f.path}');
    page = f.readAsStringSync().pipeCodeSeul();
  });

  group('le rafraîchissement attend les réponses', () {
    test('il est asynchrone', () {
      expect(page, contains('Future<void> rafraichirDonneesCompte'));
      expect(page.contains('void rafraichirDonneesCompte(WidgetRef ref) {'),
          isFalse,
          reason: 'la version synchrone rendait la main avant les réponses');
    });

    test('il attend les six providers', () {
      expect(page, contains('await Future.wait('));
      for (final p in [
        'profileProvider.future',
        'currentSubscriptionProvider.future',
        'referralStatsProvider.future',
        'userStatsProvider.future',
        'bankrollProvider.future',
        'bankrollStatsProvider.future',
      ]) {
        expect(page, contains(p), reason: '$p n\'est pas attendu');
      }
    });

    test('une panne ne fait pas échouer le geste', () {
      // Chaque carte affiche déjà son erreur ; laisser remonter l'échec ferait
      // planter le rafraîchissement au lieu de le terminer.
      expect(page, contains('catchError'));
    });
  });

  group("l'onglet Parrainage distingue ses états", () {
    test('un chargement a son propre rendu', () {
      expect(page, contains("Key('parrainage-chargement')"));
      expect(page, contains('refAsync.isLoading && !refAsync.hasValue'));
    });

    test('une panne a le sien, avec réessai', () {
      expect(page, contains("Key('parrainage-erreur')"));
      expect(page, contains('refAsync.hasError && !refAsync.hasValue'));
      expect(page, contains('ref.invalidate(referralStatsProvider)'));
    });

    test('une valeur déjà reçue continue de s\'afficher', () {
      // Contrepartie : `!refAsync.hasValue` dans les deux gardes. Sans lui, un
      // rafraîchissement en arrière-plan effacerait des données correctes pour
      // remettre une roue qui tourne.
      expect('!refAsync.hasValue'.allMatches(page).length, 2,
          reason: 'les deux gardes doivent épargner une valeur déjà connue');
    });

    test('les valeurs par défaut restent pour une réponse incomplète', () {
      // Elles couvrent une clé manquante dans une réponse **reçue** — un autre
      // cas, qui doit continuer d'être couvert.
      expect(page, contains("(stats['commission_l1']  as num?)?.toInt() ?? 500"));
    });
  });
}
