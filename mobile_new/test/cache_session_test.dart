import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/cache/cache_service.dart';
import 'package:pronowin/core/network/cache_interceptor.dart';

/// Une réponse partie avant la fin d'une session ne repeuple pas le cache du
/// compte suivant (constat M11 de l'audit du 24 septembre 2026).
///
/// Le cache HTTP garde les réponses sous une clé qui ne dit pas à quel compte
/// elles appartiennent. Déconnexion et session expirée le vident ; mais une
/// requête déjà partie répondait ensuite, et réécrivait dans le cache vide les
/// données du compte précédent.
class _AdaptateurLent implements HttpClientAdapter {
  /// Terminé quand la requête a quitté l'application — elle est « en vol ».
  final Completer<void> demandee = Completer<void>();
  final Completer<void> reponse = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? corps, Future<void>? annulation) async {
    if (!demandee.isCompleted) demandee.complete();
    await reponse.future;
    return ResponseBody.fromString(jsonEncode({'solde': 125000}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Dio> client(_AdaptateurLent adaptateur) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))
      ..httpClientAdapter = adaptateur
      ..interceptors.add(CacheInterceptor());
    return dio;
  }

  test('une réponse arrivée après la fin de la session n\'est pas gardée', () async {
    final adaptateur = _AdaptateurLent();
    final dio = await client(adaptateur);

    final requete = dio.get('/bankroll');
    await adaptateur.demandee.future;
    // Déconnexion, ou session expirée, pendant que la requête est en vol.
    await CacheService.clearAll();
    adaptateur.reponse.complete();
    await requete;

    expect(await CacheService.loadStale<dynamic>('/bankroll', (d) => d), isNull);
  });

  test('une réponse de la même session est gardée', () async {
    // Contrepartie : sans elle, un intercepteur qui ne garderait plus rien
    // passerait le point précédent.
    final adaptateur = _AdaptateurLent();
    final dio = await client(adaptateur);
    final requete = dio.get('/bankroll');
    adaptateur.reponse.complete();
    await requete;

    expect(await CacheService.loadStale<dynamic>('/bankroll', (d) => d), {'solde': 125000});
  });

  test('vider le cache change de génération', () async {
    final avant = CacheService.generation;
    await CacheService.clearAll();
    expect(CacheService.generation, avant + 1);
  });
}
