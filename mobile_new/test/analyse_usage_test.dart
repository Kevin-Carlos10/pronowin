import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/services/analyse_usage.dart';

/// Le plan d'analyse d'usage (constat M2 de l'audit du 24 septembre 2026) :
/// des événements d'entonnoir, sans donnée personnelle.
void main() {
  final recus = <(String, Map<String, Object>)>[];

  setUp(() {
    recus.clear();
    AnalyseUsage.espion = (nom, parametres) => recus.add((nom, parametres));
  });
  tearDown(() => AnalyseUsage.espion = null);

  test('une connexion distingue l\'inscription du retour', () async {
    await AnalyseUsage.connexion(methode: 'email', nouveauCompte: true);
    await AnalyseUsage.connexion(methode: 'google', nouveauCompte: false);
    expect(recus.map((e) => [e.$1, e.$2]).toList(), [
      ['inscription', {'methode': 'email'}],
      ['login', {'methode': 'google'}],
    ]);
  });

  test('l\'entonnoir de paiement, étape par étape', () async {
    await AnalyseUsage.paywallVu();
    await AnalyseUsage.methodeChoisie('direct');
    await AnalyseUsage.preuveEnvoyee(methode: 'direct', duree: 'mensuel');
    expect(recus.map((e) => e.$1), ['paywall_vu', 'methode_choisie', 'preuve_envoyee']);
    expect(recus.last.$2, {'methode': 'direct', 'duree': 'mensuel'});
  });

  test('Premium actif : une fois par échéance, pas à chaque ouverture du profil', () async {
    final vus = <String>{};
    Future<void> constater(String? echeance) => AnalyseUsage.premiumConstate(
      echeance: echeance, dejaVu: (c) async => vus.contains(c), marquer: (c) async => vus.add(c));

    await constater('2026-10-24T00:00:00Z');
    await constater('2026-10-24T00:00:00Z');
    await constater(null);                               // pas d'échéance connue : rien
    await constater('2026-11-24T00:00:00Z');             // renouvellement : à nouveau
    expect(recus.map((e) => e.$1), ['premium_active', 'premium_active']);
  });

  test('aucun paramètre ne porte une donnée personnelle', () async {
    await AnalyseUsage.pronosticOuvert(premium: true);
    await AnalyseUsage.pariEnregistre(5);
    await AnalyseUsage.miseConfirmee(corrigee: true);
    await AnalyseUsage.notificationOuverte('');
    await AnalyseUsage.achatStoreLance('annuel');
    // Des méthodes, des notes, des booléens : aucune adresse, aucun numéro,
    // aucun identifiant de compte.
    final valeurs = recus.expand((e) => e.$2.values).map((v) => '$v');
    expect(valeurs.where((v) => v.contains('@') || RegExp(r'\d{6,}').hasMatch(v)), isEmpty);
    expect(recus.firstWhere((e) => e.$1 == 'notification_ouverte').$2, {'type': 'inconnu'});
  });

  test('sans Firebase, un événement ne lève rien', () async {
    AnalyseUsage.espion = null;
    await expectLater(AnalyseUsage.paywallVu(), completes);
  });
}
