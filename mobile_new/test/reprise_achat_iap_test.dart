import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/abonnement/data/file_verifications.dart';
import 'package:pronowin/features/abonnement/data/iap_service.dart';

/// Un achat payé que le serveur n'a pas confirmé ne doit pas se perdre.
///
/// Quand `/subscriptions/iap/verify` échoue, l'achat est déjà encaissé par le
/// store. L'application le finalise quand même — une transaction laissée en
/// suspens est resoumise par StoreKit à chaque lancement, indéfiniment — mais
/// finaliser veut dire que le store considère l'affaire close : il ne rejouera
/// rien.
///
/// L'écran promettait pourtant : « Rouvre l'app dans un instant ou touche
/// « Restaurer mes achats » ». Rouvrir ne faisait rien du tout. Seul le bouton
/// marchait, à condition que l'acheteur y pense — et c'est la moitié fausse de
/// la promesse sur laquelle quelqu'un qui vient de payer se repose.
///
/// La trace tient donc dans cette file, relue au démarrage.
void main() {
  const apple = (store: 'apple', receipt: '2000000912345678');
  const google = (store: 'google', receipt: 'jeton-google-abc');

  group("la file retient ce qu'on doit encore vérifier", () {
    test('une charge ajoutée se relit', () {
      final f = ajouterA(const [], apple);
      expect(f, hasLength(1));
      expect(decoderFile(encoderFile(f)), [apple]);
    });

    test("le même achat n'est pas mis deux fois", () {
      // Une reprise qui retombe sur la même coupure réseau réessaie la même
      // charge. Sans dédoublonnage, la file grossirait à chaque tentative.
      var f = ajouterA(const [], apple);
      f = ajouterA(f, apple);
      f = ajouterA(f, apple);
      expect(f, hasLength(1));
    });

    test('deux achats distincts coexistent', () {
      // Contrepartie : un dédoublonnage trop large effacerait un vrai second
      // achat — par exemple un abonnement racheté après un remboursement.
      var f = ajouterA(const [], apple);
      f = ajouterA(f, google);
      expect(f, hasLength(2));
    });

    test('une charge vérifiée est retirée', () {
      var f = ajouterA(ajouterA(const [], apple), google);
      f = retirerDe(f, apple);
      expect(f, [google]);
    });

    test("retirer ce qui n'y est pas ne change rien", () {
      final f = ajouterA(const [], apple);
      expect(retirerDe(f, google), [apple]);
    });
  });

  group("la lecture résiste à ce qu'elle trouve", () {
    test('rien stocké donne une file vide', () {
      expect(decoderFile(null), isEmpty);
      expect(decoderFile(''), isEmpty);
      expect(decoderFile('   '), isEmpty);
    });

    test('une valeur abîmée donne une file vide, sans lever', () {
      // Perdre la reprise est fâcheux ; empêcher l'application de démarrer à
      // cause d'une préférence corrompue le serait davantage.
      expect(decoderFile('{ pas du json'), isEmpty);
      expect(decoderFile('"une chaîne"'), isEmpty);
      expect(decoderFile('[1, 2, 3]'), isEmpty);
    });

    test('les entrées incomplètes sont écartées', () {
      // Une charge sans reçu ne peut rien vérifier : la garder ferait
      // réessayer indéfiniment un appel qui échouera toujours.
      const brut = '[{"store":"apple"},{"receipt":"x"},'
          '{"store":"google","receipt":"bon"}]';
      expect(decoderFile(brut), [(store: 'google', receipt: 'bon')]);
    });
  });

  group('la file complète, avec son stockage', () {
    test('ajoute, relit et retire', () async {
      final stockage = _StockageMemoire();
      final file = FileVerifications(stockage);

      expect(await file.lire(), isEmpty);

      await file.ajouter(apple);
      await file.ajouter(google);
      expect(await file.lire(), hasLength(2));

      await file.retirer(apple);
      expect(await file.lire(), [google]);
    });

    test('ce qui est écrit survit à une nouvelle instance', () async {
      // C'est tout l'intérêt : la reprise a lieu au lancement suivant, donc
      // dans un autre objet que celui qui a subi l'échec.
      final stockage = _StockageMemoire();
      await FileVerifications(stockage).ajouter(apple);

      expect(await FileVerifications(stockage).lire(), [apple]);
    });
  });

  /// Ce qui précède éprouve la file ; ceci éprouve la décision de s'en servir.
  ///
  /// La file la mieux écrite ne sert à rien si l'échec n'y met rien, ou si un
  /// succès n'en retire rien — auquel cas on revérifierait le même achat à
  /// chaque lancement, pour toujours.
  group("l'échec met en file, le succès en retire", () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test("un serveur injoignable garde l'achat rattrapable", () async {
      final file = FileVerifications(_StockageMemoire());
      final svc = IapService(_DioQuiEchoue(), file: file);

      await svc.envoyerVerification(apple);

      expect(await file.lire(), [apple],
          reason: "sans cela, l'achat payé est définitivement perdu");
    });

    test("une confirmation retire l'achat de la file", () async {
      final file = FileVerifications(_StockageMemoire());
      await file.ajouter(apple);

      final svc = IapService(
        _DioQuiRepond({
          'active': true,
          'expires_at':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        }),
        file: file,
      );

      await svc.envoyerVerification(apple, estReprise: true);

      expect(await file.lire(), isEmpty,
          reason: 'sinon le même achat serait revérifié à chaque lancement');
    });

    test('un abonnement inactif sort aussi de la file', () async {
      // Contrepartie : le serveur a répondu. Renvoyer le même reçu ne le
      // rendra pas actif — le garder en file, c'est boucler pour rien.
      final file = FileVerifications(_StockageMemoire());
      await file.ajouter(apple);

      final svc = IapService(
        _DioQuiRepond({'active': false, 'status': 'expired'}),
        file: file,
      );
      await svc.envoyerVerification(apple, estReprise: true);

      expect(await file.lire(), isEmpty);
    });

    test("une reprise qui échoue ne prévient pas l'utilisateur", () async {
      // Personne n'a rien demandé : afficher un échec au démarrage
      // inquiéterait sans raison. La charge reste simplement en file.
      final file = FileVerifications(_StockageMemoire());
      final svc = IapService(_DioQuiEchoue(), file: file);

      final recus = <IapResult>[];
      final sub = svc.results.listen(recus.add);
      await svc.envoyerVerification(apple, estReprise: true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(recus, isEmpty);
      expect(await file.lire(), [apple]);
    });

    test("un échec sur l'achat d'origine, lui, se dit", () async {
      // Contrepartie : quelqu'un vient de payer et attend une réponse.
      final file = FileVerifications(_StockageMemoire());
      final svc = IapService(_DioQuiEchoue(), file: file);

      final recus = <IapResult>[];
      final sub = svc.results.listen(recus.add);
      await svc.envoyerVerification(apple);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(recus, hasLength(1));
      expect(recus.first, isA<IapFailure>());
    });
  });
}

/// Un stockage en mémoire, pour éprouver la file sans le plugin.
class _StockageMemoire implements StockageFile {
  String? _valeur;

  @override
  Future<String?> lire() async => _valeur;

  @override
  Future<void> ecrire(String valeur) async => _valeur = valeur;
}

/// Un serveur injoignable.
class _DioQuiEchoue implements Dio {
  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    throw DioException(requestOptions: RequestOptions(path: path));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Un serveur qui répond ce qu'on lui a dit de répondre.
class _DioQuiRepond implements Dio {
  _DioQuiRepond(this.corps);

  final Map<String, dynamic> corps;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: corps as T,
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
