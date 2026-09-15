import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/cache/cache_service.dart';
import 'package:pronowin/core/network/failures.dart';
import 'package:pronowin/features/pronostics/data/models/match_model.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/domain/repositories/pronostics_repository.dart';
import 'package:pronowin/features/pronostics/domain/usecases/get_matches_usecase.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';

/// Hors connexion, la dernière copie vaut mieux qu'un écran d'erreur.
///
/// ── Un repli placé là où rien n'arrive ────────────────────────────────────
///
/// Le dépôt convertit toute erreur réseau en `Left(Failure)` : il ne lève
/// jamais. Le repli de cache était pourtant écrit dans le `catch` du provider,
/// qui ne recevait donc rien. C'était du code mort : une coupure réseau donnait
/// un écran d'erreur alors qu'une copie utilisable dormait dans les
/// préférences.
///
/// ── Et un repli qui n'aurait presque jamais servi ─────────────────────────
///
/// Il appelait `CacheService.load`, qui rend `null` dès le TTL dépassé — cinq
/// minutes pour les pronostics. Même placé au bon endroit, il n'aurait
/// fonctionné que dans les cinq minutes suivant le dernier chargement réussi.
/// Hors connexion, une copie périmée vaut mieux que rien, à condition de dire
/// de quand elle date.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// La clé que le provider construit pour ses filtres par défaut.
  const cle = 'matches_all_past30_all_all_false';

  MatchModel match(String id) => MatchModel(
        id: id,
        league: 'Ligue 1',
        leagueCountry: 'France',
        homeTeam: 'PSG',
        awayTeam: 'OM',
        matchDate: DateTime.utc(2026, 9, 20, 18),
        status: MatchStatus.upcoming,
        predictionType: PredictionType.over25,
        predictionLabel: '+2.5 buts',
        oddsRecommended: 1.9,
        oddsHome: 1.8,
        oddsDraw: 3.4,
        oddsAway: 4.2,
        confidenceScore: 4,
        isPremium: false,
        homeFormPoints: 10,
        awayFormPoints: 7,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// Construit le notifier avec un dépôt qui répond ce qu'on lui dit.
  MatchesPaginatedNotifier notifier(
          Either<Failure, MatchesPageResult> reponse) =>
      MatchesPaginatedNotifier(
        GetMatchesUseCase(_DepotFixe(reponse)), const PronosticsFilter(),
        null, false);

  /// Attend que le chargement initial se termine.
  Future<void> attendre(MatchesPaginatedNotifier n) async {
    for (var i = 0; i < 50 && n.state.isInitialLoading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('une coupure réseau sert la copie', () {
    test('le repli se déclenche sur un échec, pas sur une exception', () async {
      await CacheService.save(cle, [match('m1').toJson()]);

      final n = notifier(Left(NetworkFailure()));
      await attendre(n);

      expect(n.state.matches, hasLength(1),
          reason: 'le repli vivait dans un `catch` que rien n\'atteignait');
      expect(n.state.error, isNull);
      expect(n.state.cacheDe, isNotNull, reason: 'l\'âge doit être connu');
    });

    test('une copie périmée reste servie', () async {
      // `load` rendait `null` au-delà de cinq minutes. `loadWithMeta` la rend
      // quand même — c'est tout l'intérêt hors connexion.
      SharedPreferences.setMockInitialValues({
        'cache_$cle': '{"ts":${DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch},'
            '"data":[${_json(match('m-vieux'))}]}',
      });

      final n = notifier(Left(NetworkFailure()));
      await attendre(n);

      expect(n.state.matches, hasLength(1));
      expect(n.state.cacheDe, isNotNull);
      expect(
          DateTime.now().difference(n.state.cacheDe!).inHours,
          greaterThan(24));
    });

    test('sans copie, l\'erreur reste une erreur', () async {
      // Contrepartie : un repli qui masquerait l'échec sans rien à montrer
      // laisserait l'écran vide et muet.
      final n = notifier(Left(NetworkFailure()));
      await attendre(n);

      expect(n.state.matches, isEmpty);
      expect(n.state.error, isNotNull);
      expect(n.state.cacheDe, isNull);
    });

    test('une copie vide ne vaut pas mieux que rien', () async {
      await CacheService.save(cle, <dynamic>[]);

      final n = notifier(Left(NetworkFailure()));
      await attendre(n);

      expect(n.state.error, isNotNull,
          reason: 'une liste vide présentée comme des données cache l\'échec');
    });
  });

  group('le réseau reprend la main', () {
    test('une réponse fraîche efface la marque de copie', () async {
      // Contrepartie : le bandeau « hors connexion » ne doit pas survivre au
      // retour du réseau.
      //
      // Il faut partir d'un état qui porte réellement la marque : un notifier
      // neuf a `cacheDe == null` dès le départ, et le test passait alors sans
      // rien mesurer — vérifié en retirant `clearCache` du chemin de succès.
      await CacheService.save(cle, [match('vieux').toJson()]);

      final depot = _DepotVariable(Left(NetworkFailure()));
      final n = MatchesPaginatedNotifier(
          GetMatchesUseCase(depot), const PronosticsFilter(), null, false);
      await attendre(n);
      expect(n.state.cacheDe, isNotNull, reason: 'la marque doit être posée');

      depot.reponse = Right(MatchesPageResult(
          data: [match('frais')], nextCursor: null, hasMore: false));
      n.refresh();
      await attendre(n);

      expect(n.state.matches.single.id, 'frais');
      expect(n.state.cacheDe, isNull);
      expect(n.state.error, isNull);
    });
  });
}

String _json(MatchModel m) {
  final j = m.toJson();
  final paires = j.entries.map((e) {
    final v = e.value;
    if (v == null) return '"${e.key}":null';
    if (v is num || v is bool) return '"${e.key}":$v';
    return '"${e.key}":"${v.toString().replaceAll('"', r'\"')}"';
  });
  return '{${paires.join(',')}}';
}

/// Un dépôt dont la réponse change entre deux appels.
class _DepotVariable implements PronosticsRepository {
  _DepotVariable(this.reponse);
  Either<Failure, MatchesPageResult> reponse;

  @override
  Future<Either<Failure, MatchesPageResult>> getMatches({
    String? leagueId,
    String? dateFilter,
    String? sport,
    String? status,
    bool? hasPronostic,
    String? cursor,
    int limit = 20,
  }) async =>
      reponse;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Un dépôt qui rend toujours la même réponse.
class _DepotFixe implements PronosticsRepository {
  _DepotFixe(this._reponse);
  final Either<Failure, MatchesPageResult> _reponse;

  @override
  Future<Either<Failure, MatchesPageResult>> getMatches({
    String? leagueId,
    String? dateFilter,
    String? sport,
    String? status,
    bool? hasPronostic,
    String? cursor,
    int limit = 20,
  }) async =>
      _reponse;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
