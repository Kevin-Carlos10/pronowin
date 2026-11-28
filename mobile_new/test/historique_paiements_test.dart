import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/pages/historique_paiements_page.dart';

/// L'historique des paiements et leurs reçus (23 novembre 2026).
void main() {
  setUpAll(() async => initializeDateFormatting('fr'));

  final paye = LignePaiement.fromJson({
    'id': 's1', 'date': '2026-11-12T10:00:00Z', 'statut': 'paye', 'formule': 'premium_annual',
    'montant': 54000, 'moyen': 'geniuspay', 'operateur': 'orange_money', 'reference': 'GP-123',
    'debut': '2026-11-12T10:00:00Z', 'fin': '2027-11-12T10:00:00Z',
  });
  final refuse = LignePaiement.fromJson({
    'id': 'p2', 'date': '2026-11-10T10:00:00Z', 'statut': 'refuse', 'formule': 'premium_monthly',
    'montant': 5000, 'moyen': 'manual_mobcash', 'motif': 'Montant incomplet',
  });
  final enCours = LignePaiement.fromJson({
    'id': 'g2', 'date': '2026-11-22T10:00:00Z', 'statut': 'en_cours', 'formule': 'premium_monthly',
    'montant': 6000, 'moyen': 'geniuspay',
  });

  Future<void> monter(WidgetTester t, List<LignePaiement> lignes) async {
    await t.pumpWidget(ProviderScope(
      overrides: [historiquePaiementsProvider.overrideWith((ref) async => lignes)],
      child: MaterialApp(theme: AppTheme.dark, locale: const Locale('fr'),
        home: const HistoriquePaiementsPage()),
    ));
    await t.pumpAndSettle();
  }

  test('les opérateurs par leur nom', () {
    expect(nomOperateur('orange_money'), 'Orange Money');
    expect(nomOperateur('moov_money'), 'Moov Money');
    expect(nomOperateur('mon_operateur'), 'Mon Operateur');
  });

  testWidgets('chaque paiement : formule, date et moyen, montant, statut', (t) async {
    await monter(t, [enCours, paye, refuse]);
    expect(find.text('Premium annuel'), findsOneWidget);
    expect(find.textContaining('Mobile Money (Orange Money)'), findsOneWidget);
    expect(find.text('54 000 FCFA'), findsOneWidget);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('Refusé'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('un paiement abouti a son reçu, à partager, référence et période comprises', (t) async {
    await monter(t, [paye]);
    await t.tap(find.byKey(const Key('paiement-s1')));
    await t.pumpAndSettle();
    expect(find.text('Reçu'), findsOneWidget);
    expect(find.text('GP-123'), findsOneWidget);
    expect(find.textContaining('du 12 novembre 2026 au 12 novembre 2027'), findsOneWidget);
    expect(find.byKey(const Key('recu-partager')), findsOneWidget);
    expect(find.byKey(const Key('recu-support')), findsOneWidget);
  });

  testWidgets('un refus dit pourquoi ; rien à partager, mais le support', (t) async {
    await monter(t, [refuse]);
    await t.tap(find.byKey(const Key('paiement-p2')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('recu-motif')), findsOneWidget);
    expect(find.text('Motif : Montant incomplet'), findsOneWidget);
    expect(find.byKey(const Key('recu-partager')), findsNothing);
    expect(find.byKey(const Key('recu-support')), findsOneWidget);
  });

  testWidgets('aucun paiement : on dit ce qui s\'affichera ici', (t) async {
    await monter(t, const []);
    expect(find.textContaining('Aucun paiement pour l\'instant'), findsOneWidget);
  });
}
