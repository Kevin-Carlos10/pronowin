import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/storage/secure_storage.dart';
import 'package:pronowin/features/parametres/presentation/pages/membres_bloques_page.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/moderation_commentaire.dart';
import 'package:pronowin/l10n/catalog_en.dart';

/// Signaler un commentaire, bloquer un membre (règle 1.2 de l'App Store).
///
/// Le serveur simulé enregistre ce que l'application lui envoie : c'est ce
/// qui compte, l'écran ne fait que le déclencher.
class _StockageMemoire extends SecureStorageService {
  final Map<String, String> valeurs = {};
  @override
  Future<String?> read(String key) async => valeurs[key];
  @override
  Future<void> write(String key, String value) async => valeurs[key] = value;
  @override
  Future<void> deleteAll() async => valeurs.clear();
}

class _Serveur implements HttpClientAdapter {
  final requetes = <({String methode, String chemin, Object? corps})>[];
  List<Map<String, dynamic>> bloques = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? flux, Future<void>? annulation) async {
    final brut = flux == null ? '' : utf8.decode(await flux.expand((x) => x).toList());
    requetes.add((methode: o.method, chemin: o.path, corps: brut.isEmpty ? null : jsonDecode(brut)));
    Object reponse = {};
    if (o.method == 'GET' && o.path.startsWith('/comments/')) {
      reponse = {
        'comments': [
          _commentaire('c1', 'u-autre', 'Kofi', 'Avis tranché sur ce match', false),
          _commentaire('c2', 'u-expert', 'Expert PronoWin', 'Réponse de l\'analyste', true),
        ],
        'vote': {'userVote': null, 'agree': 0, 'disagree': 0, 'total': 0},
      };
    } else if (o.method == 'GET' && o.path == '/moderation/blocages') {
      reponse = {'data': bloques};
    }
    return ResponseBody.fromString(jsonEncode(reponse), o.method == 'POST' ? 201 : 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  static Map<String, dynamic> _commentaire(String id, String userId, String pseudo, String texte, bool expert) => {
    'id': id, 'userId': userId, 'content': texte, 'isExpert': expert, 'parentId': null,
    'createdAt': '2026-10-01T10:00:00Z', 'user': {'pseudo': pseudo, 'avatarUrl': null}, 'replies': [],
  };

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Serveur serveur;

  Future<void> monter(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    serveur = _Serveur();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = serveur;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        secureStorageProvider.overrideWithValue(_StockageMemoire()),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ecran))),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Démonte et laisse courir l'horloge : la session (authProvider) pose des
  /// minuteries que le banc rejetterait encore en vol.
  Future<void> demonter(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('le commentaire d\'un membre a son menu ; celui de l\'analyste non', (tester) async {
    await monter(tester, const CommentsSection(pronosticId: 'p1'));
    expect(find.text('Avis tranché sur ce match'), findsOneWidget);
    expect(find.byTooltip('Signaler ou bloquer'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('signaler envoie le commentaire et le motif choisi', (tester) async {
    await monter(tester, const CommentsSection(pronosticId: 'p1'));
    await tester.tap(find.byTooltip('Signaler ou bloquer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();

    expect(find.text('Signaler ce commentaire'), findsOneWidget);
    await tester.tap(find.text('Insulte ou harcèlement'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Signaler'));
    await tester.pump(const Duration(seconds: 1));

    final envoi = serveur.requetes.singleWhere((r) => r.chemin == '/moderation/signalements');
    expect(envoi.methode, 'POST');
    expect(envoi.corps, {'comment_id': 'c1', 'motif': 'insulte'});
    await demonter(tester);
  });

  testWidgets('bloquer demande confirmation, puis envoie le membre', (tester) async {
    await monter(tester, const CommentsSection(pronosticId: 'p1'));
    await tester.tap(find.byTooltip('Signaler ou bloquer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquer Kofi'));
    await tester.pumpAndSettle();

    expect(find.text('Bloquer Kofi ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bloquer'));
    await tester.pump(const Duration(seconds: 1));

    final envoi = serveur.requetes.singleWhere((r) => r.chemin == '/moderation/blocages');
    expect(envoi.corps, {'user_id': 'u-autre'});
    await demonter(tester);
  });

  testWidgets('les membres bloqués se débloquent depuis les Paramètres', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    serveur = _Serveur()..bloques = [{'user_id': 'u-autre', 'pseudo': 'Kofi', 'avatar_url': null}];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = serveur;
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: MembresBloquesPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Kofi'), findsOneWidget);
    await tester.tap(find.text('Débloquer'));
    await tester.pumpAndSettle();
    expect(serveur.requetes.where((r) => r.methode == 'DELETE').single.chemin, '/moderation/blocages/u-autre');
  });

  test('les refus du serveur sont traduits par leur code', () {
    expect(englishMessages, contains('Ce commentaire contient des termes interdits par les règles de la communauté.'));
    expect(englishMessages, contains('Les liens ne sont pas autorisés dans les commentaires.'));
    expect(englishMessages, contains('Les numéros de téléphone ne sont pas autorisés dans les commentaires.'));
  });

  test('chaque motif de signalement a sa traduction', () {
    // Passés à `tr()` par variable : l'audit des clés ne les voit pas.
    for (final (_, libelle) in motifsSignalement) {
      expect(englishMessages, contains(libelle), reason: libelle);
    }
  });

  test('le nombre de buts reste traduit', () {
    // Retirées à tort du catalogue le 1er octobre 2026 : la clé est écrite
    // dans une chaîne imbriquée, que l'outil de ménage n'a pas su lire.
    expect(englishMessages['{arg0} but'], '{arg0} goal');
    expect(englishMessages['{arg0} buts'], '{arg0} goals');
  });
}
