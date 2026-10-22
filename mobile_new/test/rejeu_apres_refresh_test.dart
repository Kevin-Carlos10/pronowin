import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/constants/app_constants.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/storage/secure_storage.dart';

/// Un rejeu qui échoue ne doit pas se faire passer pour une absence de compte.
///
/// Le jeton d'accès vit quinze minutes. Quand il expire pendant le chargement
/// d'un écran, l'intercepteur rafraîchit puis rejoue la requête. Ce rejeu part
/// au milieu d'une rafale — un délai dépassé y est banal.
///
/// L'intercepteur renvoyait alors le **401 d'origine**, quelle qu'ait été la
/// cause réelle. Or dans cette application 401 ne veut pas dire « ça a raté » :
/// il veut dire « pas de compte ». Les écrans le lisent ainsi et proposent d'en
/// créer un. Constaté sur l'émulateur, session valide et `/auth/profile`
/// répondant : la fiche de match affichait « Crée ton compte pour voir
/// l'analyse » à un utilisateur connecté.
///
/// Rien ne plantait, rien n'était journalisé, et l'écran affirmait le faux.
///
/// Les deux sens comptent — un intercepteur qui ne signalerait plus jamais de
/// 401 laisserait passer les vraies fins de session sans que personne ne soit
/// invité à se reconnecter.

/// Stockage en mémoire : le vrai passe par un canal de plateforme absent des
/// tests.
class _StockageMemoire extends SecureStorageService {
  final Map<String, String> valeurs = {};

  @override
  Future<String?> read(String key) async => valeurs[key];

  @override
  Future<void> write(String key, String value) async => valeurs[key] = value;

  @override
  Future<void> deleteAll() async => valeurs.clear();
}

/// Adaptateur scénarisé : premier appel refusé, rafraîchissement accepté,
/// rejeu selon le cas testé.
class _Adaptateur implements HttpClientAdapter {
  _Adaptateur({required this.auRejeu});

  /// Ce que renvoie le rejeu — l'objet du test.
  final Object Function() auRejeu;

  int appelsCible = 0;
  final List<String> chemins = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    chemins.add(options.path);

    if (options.path.contains(ApiEndpoints.refreshToken)) {
      return ResponseBody.fromString(
        jsonEncode({'access_token': 'neuf', 'refresh_token': 'neuf-r'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    appelsCible++;
    if (appelsCible == 1) {
      // Jeton expiré : c'est ce 401 qui déclenche le rafraîchissement.
      return ResponseBody.fromString('{"message":"expiré"}', 401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
    }

    final resultat = auRejeu();
    if (resultat is ResponseBody) return resultat;
    throw resultat;
  }

  @override
  void close({bool force = false}) {}
}

({Dio dio, _Adaptateur adaptateur, _StockageMemoire stockage}) monter(
    Object Function() auRejeu) {
  final stockage = _StockageMemoire()
    ..valeurs[AppConstants.accessTokenKey]  = 'vieux'
    ..valeurs[AppConstants.refreshTokenKey] = 'vieux-r';

  // On passe par un provider maison plutôt que par `dioProvider` : ce dernier
  // installe la télémétrie Firebase, absente des tests.
  final clientProvider = Provider<DioClient>(
    (ref) => DioClient(stockage, ref, telemetrie: false));

  final conteneur = ProviderContainer();
  addTearDown(conteneur.dispose);

  final adaptateur = _Adaptateur(auRejeu: auRejeu);

  // Le rafraîchissement passe par un Dio vierge (cf. la couture dans
  // DioClient) : sans cette ligne il sortirait sur le vrai réseau et le test
  // mesurerait la connectivité de la machine plutôt que le code.
  DioClient.fabriqueDioRafraichissement =
      () => Dio(BaseOptions(baseUrl: AppConstants.baseUrl))
        ..httpClientAdapter = adaptateur;
  addTearDown(() => DioClient.fabriqueDioRafraichissement = null);

  final dio = conteneur.read(clientProvider).dio;
  dio.httpClientAdapter = adaptateur;
  return (dio: dio, adaptateur: adaptateur, stockage: stockage);
}

void main() {
  // Le stockage sécurisé passe par un canal de plateforme : sans liaison
  // initialisée, son accès avertit bruyamment au milieu des résultats.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un rejeu qui expire ne devient pas un 401', () async {
    final m = monter(() => DioException.connectionTimeout(
      timeout:        const Duration(seconds: 1),
      requestOptions: RequestOptions(path: '/pronostics/x/ai-analyze'),
    ));

    DioException? vue;
    try {
      await m.dio.get('/pronostics/x/ai-analyze');
    } on DioException catch (e) {
      vue = e;
    }

    expect(vue, isNotNull, reason: 'la requête aurait dû échouer');
    expect(m.adaptateur.appelsCible, 2,
      reason: 'le rejeu n\'a pas eu lieu : le test ne prouve rien');
    expect(vue!.response?.statusCode, isNot(401),
      reason: 'un délai dépassé remonte en 401 — les écrans en concluent '
              '« pas de compte » et proposent d\'en créer un');
    expect(vue.type, DioExceptionType.connectionTimeout);
  });

  test('un rejeu refusé reste un 401', () async {
    // L'autre sens : le jeton neuf a vraiment été rejeté. La session est
    // finie, et l'application doit pouvoir le dire.
    final m = monter(() => ResponseBody.fromString('{"message":"refusé"}', 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      }));

    DioException? vue;
    try {
      await m.dio.get('/pronostics/x/ai-analyze');
    } on DioException catch (e) {
      vue = e;
    }

    expect(vue, isNotNull);
    expect(m.adaptateur.appelsCible, 2);
    expect(vue!.response?.statusCode, 401);
  });

  // La carte d'analyse est une classe privée de `match_detail_page.dart` : un
  // test de rendu devrait monter la page entière et toutes ses dépendances.
  // Le dépôt garde déjà ses surfaces privées par le texte source
  // (`canal_store_test.dart`) ; ce contrôle suit la même règle, et
  // `tool/injections_session.py` vérifie qu'il mord.
  test("l'écran ne conclut pas « pas de compte » sur le seul code HTTP", () {
    final source = File(
      'lib/features/pronostics/presentation/pages/match_detail/analyse_ia.dart',
    ).readAsStringSync();

    final branche = source.indexOf('nonConnecte: true');
    expect(branche, greaterThan(-1),
      reason: 'branche invité introuvable : le test ne prouve plus rien');

    final garde = source.indexOf('effectiveLoggedInProvider');
    expect(garde, greaterThan(-1),
      reason: "la branche invité ne consulte plus l'état de session : un 401 "
              'transitoire proposera de créer un compte à un utilisateur '
              'connecté');
    expect(garde, lessThan(branche),
      reason: "la garde doit précéder la branche qu'elle conditionne");
  });

  test('un rejeu qui aboutit rend la réponse', () async {
    final m = monter(() => ResponseBody.fromString(
      jsonEncode({'probability': 72, 'explanation': 'ok'}), 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      }));

    final r = await m.dio.get('/pronostics/x/ai-analyze');

    expect(r.statusCode, 200);
    expect(r.data['probability'], 72);
    // Le rafraîchissement a bien eu lieu, et le jeton neuf est en stockage.
    expect(m.stockage.valeurs[AppConstants.accessTokenKey], 'neuf');
  });
}
