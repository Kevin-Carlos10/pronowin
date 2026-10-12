import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/cache/cache_service.dart';
import '../../domain/entities/tutorial_entity.dart';
import 'package:pronowin/core/config/sans_pari.dart';

final tutorielsProvider = FutureProvider.autoDispose<List<TutorialEntity>>((ref) async {
  // Sur iPhone, les tutoriels qui enseignent à parier sont écartés : value
  // bet, bankroll, martingale, trading (`sansPariProvider`).
  final sansPari = ref.watch(sansPariProvider);
  final tous = await _tutoriels(ref);
  return sansPari
      ? tous.where((t) => !categoriesTutorielsPari.contains(t.category.toLowerCase())).toList()
      : tous;
});

Future<List<TutorialEntity>> _tutoriels(Ref ref) async {
  const cacheKey = 'tutoriels';
  try {
    final r    = await ref.read(dioProvider).get('/tutorials');
    final data = r.data as List<dynamic>? ?? [];
    final tutos = data.map((e) =>
      TutorialEntity.fromJson(e as Map<String, dynamic>)).toList();
    await CacheService.save(cacheKey, data);
    return tutos;
  } catch (_) {
    final cached = await CacheService.load<List<TutorialEntity>>(
      cacheKey,
      (d) => (d as List).map((e) => TutorialEntity.fromJson(e as Map<String, dynamic>)).toList(),
    );
    if (cached != null) return cached;
    rethrow;
  }
}

final selectedCategoryProvider = StateProvider<String?>((ref) => null);
final selectedLevelProvider    = StateProvider<TutorialLevel?>((ref) => null);
final searchQueryProvider      = StateProvider<String>((ref) => '');
