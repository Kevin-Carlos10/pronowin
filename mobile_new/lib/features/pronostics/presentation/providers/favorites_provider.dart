import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/models/match_model.dart';
import '../../domain/entities/match_entity.dart';

class FavoritesState {
  final Set<String> matchIds;
  final Set<String> leagues;

  const FavoritesState({this.matchIds = const {}, this.leagues = const {}});

  FavoritesState copyWith({Set<String>? matchIds, Set<String>? leagues}) =>
      FavoritesState(
        matchIds: matchIds ?? this.matchIds,
        leagues:  leagues  ?? this.leagues,
      );
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  final Ref _ref;
  FavoritesNotifier(this._ref) : super(const FavoritesState()) {
    _load();
  }

  static const _kMatches = 'fav_matches';
  static const _kLeagues = 'fav_leagues';

  Future<void> _load() async {
    // 1. Charger depuis SharedPreferences (instantané)
    final p = await SharedPreferences.getInstance();
    final localIds = Set<String>.from(p.getStringList(_kMatches) ?? []);
    state = FavoritesState(
      matchIds: localIds,
      leagues:  Set.from(p.getStringList(_kLeagues) ?? []),
    );

    // 2. Syncer les IDs depuis le backend (source de vérité)
    try {
      final dio  = _ref.read(dioProvider);
      final resp = await dio.get('/favorites');
      final list = resp.data as List<dynamic>;
      final remoteIds = list
          .map((e) => (e as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (remoteIds != localIds) {
        state = state.copyWith(matchIds: remoteIds);
        await p.setStringList(_kMatches, remoteIds.toList());
      }
    } catch (_) {
      // Backend inaccessible — on garde les IDs locaux
    }
  }

  Future<void> toggleMatch(String id) async {
    final ids     = Set<String>.from(state.matchIds);
    final adding  = !ids.contains(id);
    adding ? ids.add(id) : ids.remove(id);
    state = state.copyWith(matchIds: ids);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kMatches, ids.toList());
    // Subscribe / unsubscribe from FCM topic for this match
    try {
      final topic = 'match_$id';
      if (adding) {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      }
    } catch (_) {}

    // Sync avec le backend (fire-and-forget)
    try {
      final dio = _ref.read(dioProvider);
      if (adding) {
        await dio.post('/favorites/$id');
      } else {
        await dio.delete('/favorites/$id');
      }
    } catch (_) {}
  }

  Future<void> toggleLeague(String league) async {
    final ls = Set<String>.from(state.leagues);
    ls.contains(league) ? ls.remove(league) : ls.add(league);
    state = state.copyWith(leagues: ls);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLeagues, ls.toList());
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>(
  (ref) => FavoritesNotifier(ref),
);

/// Liste complète des matchs favoris depuis le backend (avec pronostic intégré).
/// Invalidé automatiquement quand l'utilisateur toggle un favori.
final favoritesMatchesProvider = FutureProvider.autoDispose<List<MatchEntity>>((ref) async {
  // Se réexécute quand favoritesProvider change (toggle)
  ref.watch(favoritesProvider);

  final dio  = ref.read(dioProvider);
  final resp = await dio.get('/favorites');
  final list = resp.data as List<dynamic>;
  return list
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
