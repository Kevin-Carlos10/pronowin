import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronowin/core/network/dio_client.dart';
import 'package:pronowin/features/classement/domain/entities/leaderboard_entity.dart';
import 'package:pronowin/features/classement/presentation/providers/leaderboard_provider.dart';

import 'aides/code_seul.dart';

/// Le classement ne doit jamais montrer des parieurs qui n'existent pas.
///
/// ── Ce que l'écran affichait ──────────────────────────────────────────────
///
/// Quand `/leaderboard` échouait et que le cache était vide, le provider ne
/// laissait pas l'erreur remonter : il rendait une liste de quinze parieurs
/// fabriqués, avec des taux de réussite allant de 65 à 87 %. L'écran les
/// affichait comme les autres — podium, badges « legend » et « expert »,
/// nombres de paris — sans la moindre mention qu'ils étaient fictifs.
///
/// ── Pourquoi c'est le pire endroit pour ça ────────────────────────────────
///
/// Sur une application de paris, un taux de réussite n'est pas un ornement :
/// c'est ce sur quoi l'utilisateur se fait une idée de ce qu'il peut espérer.
/// Annoncer 87 % à quelqu'un qui n'a aucun moyen de recouper, c'est lui donner
/// une attente fausse avant qu'il ne mise son argent.
///
/// Et le repli sortait exactement au pire moment : premier lancement, mauvaise
/// connexion, cache vide. C'est-à-dire l'utilisateur le plus neuf, sur la
/// liaison la plus faible — le public de cette application.
///
/// ── Ce qui existait déjà et ne servait à rien ─────────────────────────────
///
/// `ClassementPage` a un état d'erreur complet, avec un bouton « réessayer ».
/// Le provider avalant toutes les exceptions, cette branche ne pouvait pas
/// s'afficher. Une protection dont la condition d'activation n'est jamais
/// remplie ne protège personne : la corriger, c'est simplement cesser de lui
/// barrer la route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Un Dio qui échoue, comme sur une connexion coupée.
  Dio dioQuiEchoue() {
    final dio = Dio();
    dio.httpClientAdapter = _AdaptateurEnPanne();
    return dio;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group("l'échec remonte au lieu d'être maquillé", () {
    test('sans réseau ni cache, le provider est en erreur', () async {
      final c = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dioQuiEchoue())],
      );
      addTearDown(c.dispose);

      await expectLater(
        c.read(leaderboardProvider(LeaderboardPeriod.monthly).future),
        throwsA(isA<Object>()),
        reason: "c'est ce que `ClassementPage` attend pour afficher son état "
            "d'erreur et son bouton « réessayer »",
      );
    });

    test('il ne rend surtout pas une liste toute faite', () async {
      final c = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dioQuiEchoue())],
      );
      addTearDown(c.dispose);

      List<LeaderboardEntry>? rendu;
      try {
        rendu = await c.read(
            leaderboardProvider(LeaderboardPeriod.monthly).future);
      } catch (_) {
        rendu = null;
      }

      // Le contrôle qui compte : une liste non vide sortie d'un échec ne peut
      // venir que d'ailleurs que du serveur.
      expect(rendu, isNull,
          reason: 'un échec ne doit produire aucun classement ; toute liste '
              "rendue ici serait inventée, puisque le serveur n'a rien dit");
    });
  });

  group('les parieurs fabriqués ont disparu du code', () {
    test('aucun pseudo inventé ne subsiste', () {
      // Filtré : le commentaire du provider doit pouvoir décrire ce qui a été
      // retiré sans que ce banc se valide sur sa propre explication.
      final code = File(
        'lib/features/classement/presentation/providers/leaderboard_provider.dart',
      ).readAsStringSync().pipeCodeSeul();

      for (final pseudo in const [
        'ProMaster', 'FootballKing', 'Tipster225', 'BetWizard', 'AfroPronos',
        'BurkinaTips', 'OuagaFoot', 'AbidjanFC', 'DakarBet', 'LagosKing',
      ]) {
        expect(code, isNot(contains(pseudo)),
            reason: '$pseudo n a jamais parié : le garder en réserve, c est '
                'garder la possibilité de le réafficher');
      }
      expect(code, isNot(contains('_demoEntries')));
      expect(code, contains('rethrow'),
          reason: "l'erreur doit atteindre l'écran, qui sait déjà quoi en faire");
    });
  });
}

/// Coupe le réseau au niveau de l'adaptateur : plus fidèle qu'une exception
/// jetée à la main, puisque Dio l'emballe comme il le ferait en vrai.
class _AdaptateurEnPanne implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    throw const SocketException('connexion refusée');
  }
}
