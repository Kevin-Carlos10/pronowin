import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/bankroll/presentation/widgets/confirmation_mise.dart';

/// « Tu as bien misé 5 000 FCFA ? » — la mise réelle, demandée au résultat
/// (constat M1 de l'audit du 24 septembre 2026).
class _Serveur implements HttpClientAdapter {
  final List<({String chemin, Map<String, dynamic> corps})> requetes = [];
  int statut = 200;
  Map<String, dynamic> reponse = {};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? corps, Future<void>? annulation) async {
    final brut = corps == null ? '' : utf8.decode(await corps.expand((o) => o).toList());
    requetes.add((
      chemin: options.path,
      corps: brut.isEmpty ? <String, dynamic>{} : jsonDecode(brut) as Map<String, dynamic>,
    ));
    return ResponseBody.fromString(jsonEncode(reponse), statut,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

BankrollBet _pari() => BankrollBet(
  id: 'pari-1', pronosticId: 'p1', matchId: 'm1',
  stakedAmount: 5000, suggestedAmount: 5000, oddsUsed: 2, potentialGain: 10000,
  result: 'WIN', profit: 5000, createdAt: DateTime(2026, 9, 20),
  homeTeam: 'Lyon', awayTeam: 'Nice', league: 'Ligue 1',
  predictionLabel: 'Victoire Domicile', confidenceScore: 5, currency: 'XOF',
  aConfirmer: true,
);

void main() {
  late _Serveur serveur;

  Future<void> monter(WidgetTester tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = serveur;
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ConfirmationMise(bet: _pari())))),
    ));
  }

  setUp(() => serveur = _Serveur());

  testWidgets('la question porte la mise enregistrée, et « oui » la confirme en un geste', (tester) async {
    serveur.reponse = {'pari_id': 'pari-1', 'mise': 5000, 'corrigee': false, 'current_balance': 105000};
    await monter(tester);
    expect(find.textContaining('Tu as bien misé 5'), findsOneWidget);

    await tester.tap(find.text('Oui, c\'est ça'));
    await tester.pumpAndSettle();

    expect(serveur.requetes.single.chemin, '/bankroll/bet/pari-1/confirmer');
    expect(serveur.requetes.single.corps, isEmpty);
    expect(find.text('Mise confirmée. Merci !'), findsOneWidget);
  });

  testWidgets('« je n\'ai pas misé » envoie une mise nulle', (tester) async {
    serveur.reponse = {'pari_id': 'pari-1', 'mise': 0, 'corrigee': true, 'current_balance': 100000};
    await monter(tester);
    await tester.tap(find.text('Non, corriger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Je n\'ai pas misé'));
    await tester.pumpAndSettle();

    expect(serveur.requetes.single.corps, {'mise_reelle': 0});
    expect(find.textContaining('pas de mise sur ce pari'), findsOneWidget);
  });

  testWidgets('un montant corrigé part tel que saisi, espaces et virgule compris', (tester) async {
    serveur.reponse = {'pari_id': 'pari-1', 'mise': 3000.5, 'corrigee': true, 'current_balance': 103000};
    await monter(tester);
    await tester.tap(find.text('Non, corriger'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3 000,5');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(serveur.requetes.single.corps, {'mise_reelle': 3000.5});
  });

  testWidgets('un refus du serveur s\'affiche tel quel, et la question reste posée', (tester) async {
    serveur
      ..statut = 409
      ..reponse = {'message': 'Cette mise est déjà confirmée.', 'code': 'STAKE_ALREADY_CONFIRMED'};
    await monter(tester);
    await tester.tap(find.text('Oui, c\'est ça'));
    await tester.pumpAndSettle();

    expect(find.text('Cette mise est déjà confirmée.'), findsOneWidget);
    expect(find.text('Oui, c\'est ça'), findsOneWidget);
  });
}
