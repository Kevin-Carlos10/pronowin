import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pronowin/core/config/distribution_channel.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/core/network/entetes_app.dart';
import 'package:pronowin/core/storage/secure_storage.dart';

/// L'application dit au serveur quelle version elle est.
///
/// Le serveur l'ignorait : le panneau ne pouvait pas dire combien de membres
/// restaient sur une version ancienne, ni lesquels relancer avant de relever
/// la version minimale.

class _StockageMemoire extends SecureStorageService {
  @override
  Future<String?> read(String key) async => null;
}

/// Retient les en-têtes de chaque requête, répond 200.
class _Espion implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> entetes = {};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    entetes[options.uri.toString()] = Map.of(options.headers);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EntetesApp.reinitialiser();
    PackageInfo.setMockInitialValues(
      appName: 'PronoWin', packageName: 'com.pronowin.app',
      version: '1.0.18', buildNumber: '34', buildSignature: '');
  });

  Future<_Espion> appeler(List<String> urls, {CanalDistribution canal = CanalDistribution.direct}) async {
    final conteneur = ProviderContainer(overrides: [
      canalDistributionProvider.overrideWithValue(canal),
    ]);
    addTearDown(conteneur.dispose);
    final client = conteneur.read(Provider<DioClient>(
        (ref) => DioClient(_StockageMemoire(), ref, telemetrie: false)));
    final espion = _Espion();
    client.dio.httpClientAdapter = espion;
    for (final u in urls) {
      await client.dio.get(u);
    }
    return espion;
  }

  test('chaque requête vers l\'API porte version, build, plateforme et canal', () async {
    final espion = await appeler(['/pronostics']);
    final e = espion.entetes.values.single;
    expect(e['X-App-Version'], '1.0.18');
    expect(e['X-App-Build'], '34');
    expect(e['X-App-Plateforme'], EntetesApp.plateforme());
    expect(e['X-App-Canal'], 'direct');
  });

  test('le canal store est annoncé comme tel', () async {
    final espion = await appeler(['/pronostics'], canal: CanalDistribution.store);
    expect(espion.entetes.values.single['X-App-Canal'], 'store');
  });

  test('rien n\'est envoyé à un autre hôte que l\'API', () async {
    final espion = await appeler(['https://exemple.org/fichier.apk']);
    final e = espion.entetes.values.single;
    expect(e.keys.where((k) => k.startsWith('X-App-')), isEmpty);
  });

  test('sans information de version, la requête part quand même, sans en-tête', () async {
    PackageInfo.setMockInitialValues(
      appName: '', packageName: '', version: '', buildNumber: '', buildSignature: '');
    final espion = await appeler(['/pronostics']);
    final e = espion.entetes.values.single;
    expect(e.keys.where((k) => k.startsWith('X-App-')), isEmpty);
  });
}
