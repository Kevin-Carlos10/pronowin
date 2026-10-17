import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/constants/app_constants.dart';
import 'package:pronowin/core/storage/secure_storage.dart';
import 'package:pronowin/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:pronowin/features/auth/data/repositories/auth_repository_impl.dart';

/// Se déconnecter ferme cette session et détache cet appareil (constat I12 de
/// l'audit du 24 septembre 2026).
///
/// L'application envoyait `POST /auth/logout` sans corps : le serveur fermait
/// toutes les sessions du compte — se déconnecter d'un téléphone déconnectait
/// les autres —, et le téléphone restait inscrit aux notifications privées du
/// compte.
class _StockageMemoire extends SecureStorageService {
  final Map<String, String> valeurs = {};

  @override
  Future<String?> read(String key) async => valeurs[key];

  @override
  Future<void> write(String key, String value) async => valeurs[key] = value;

  @override
  Future<void> deleteAll() async => valeurs.clear();
}

/// Garde le corps de chaque requête, et répond 200.
class _Adaptateur implements HttpClientAdapter {
  final List<({String chemin, Map<String, dynamic> corps})> requetes = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? corps, Future<void>? annulation) async {
    final brut = corps == null ? '' : utf8.decode(await corps.expand((o) => o).toList());
    requetes.add((
      chemin: options.path,
      corps: brut.isEmpty ? <String, dynamic>{} : jsonDecode(brut) as Map<String, dynamic>,
    ));
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adaptateur adaptateur;
  late _StockageMemoire stockage;

  AuthRepositoryImpl depot({Future<String?> Function()? jetonAppareil}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.banc.invalid'))..httpClientAdapter = adaptateur;
    return AuthRepositoryImpl(AuthRemoteDataSourceImpl(dio), stockage, jetonAppareil: jetonAppareil);
  }

  setUp(() {
    adaptateur = _Adaptateur();
    stockage = _StockageMemoire()
      ..valeurs[AppConstants.accessTokenKey] = 'acces'
      ..valeurs[AppConstants.refreshTokenKey] = 'rafraichissement-de-ce-telephone';
  });

  test('la déconnexion désigne sa session et son appareil', () async {
    await depot(jetonAppareil: () async => 'jeton-fcm-de-ce-telephone').logout();

    expect(adaptateur.requetes.single.chemin, ApiEndpoints.logout);
    expect(adaptateur.requetes.single.corps, {
      'refresh_token': 'rafraichissement-de-ce-telephone',
      'fcm_token': 'jeton-fcm-de-ce-telephone',
    });
    expect(stockage.valeurs, isEmpty);
  });

  test('Firebase en panne n\'empêche pas la déconnexion', () async {
    await depot(jetonAppareil: () async => throw Exception('firebase absent')).logout();

    expect(adaptateur.requetes.single.corps, {'refresh_token': 'rafraichissement-de-ce-telephone'});
    expect(stockage.valeurs, isEmpty);
  });
}
