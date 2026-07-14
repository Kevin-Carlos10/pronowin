import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/tutorial_remote_datasource.dart';
import '../../data/repositories/tutorial_repository_impl.dart';
import '../../domain/entities/tutorial_entity.dart';
import '../../domain/repositories/tutorial_repository.dart';
import '../../domain/usecases/get_tutorials_usecase.dart';
import '../../domain/usecases/get_tutorial_detail_usecase.dart';
import '../../domain/usecases/mark_progress_usecase.dart';

// ─── DI ──────────────────────────────────────────────────────────────────────
final tutorialDataSourceProvider = Provider<TutorialRemoteDataSource>(
  (ref) => TutorialRemoteDataSourceImpl(ref.read(dioProvider)));
final tutorialRepoProvider = Provider<TutorialRepository>(
  (ref) => TutorialRepositoryImpl(ref.read(tutorialDataSourceProvider)));

// ─── Filtres ─────────────────────────────────────────────────────────────────
class TutorialFilter {
  final TutorialLevel?    level;
  final TutorialCategory? category;
  const TutorialFilter({this.level, this.category});
  TutorialFilter copyWith({TutorialLevel? level, TutorialCategory? category, bool clearLevel = false, bool clearCategory = false}) =>
      TutorialFilter(
        level:    clearLevel    ? null : (level    ?? this.level),
        category: clearCategory ? null : (category ?? this.category),
      );
}

final tutorialFilterProvider = StateProvider<TutorialFilter>((_) => const TutorialFilter());

// ─── Liste tutoriels ──────────────────────────────────────────────────────────
final tutorialsProvider = FutureProvider.autoDispose<List<TutorialEntity>>((ref) async {
  final filter = ref.watch(tutorialFilterProvider);
  final r = await GetTutorialsUseCase(ref.read(tutorialRepoProvider))
      .call(GetTutorialsParams(level: filter.level, category: filter.category));
  return r.fold((f) => throw Exception(f.message), (t) => t);
});

// ─── Détail tutoriel ──────────────────────────────────────────────────────────
final tutorialDetailProvider = FutureProvider.autoDispose.family<TutorialEntity, String>((ref, id) async {
  final r = await GetTutorialDetailUseCase(ref.read(tutorialRepoProvider)).call(id);
  return r.fold((f) => throw Exception(f.message), (t) => t);
});

// ─── Progression vidéo ────────────────────────────────────────────────────────
class VideoProgressNotifier extends StateNotifier<Map<String, int>> {
  final TutorialRepository _repo;
  VideoProgressNotifier(this._repo) : super({});

  Future<void> updateProgress(String tutorialId, int seconds, bool completed) async {
    state = {...state, tutorialId: seconds};
    await MarkProgressUseCase(_repo).call(tutorialId, seconds, completed);
  }
}

final videoProgressProvider = StateNotifierProvider<VideoProgressNotifier, Map<String, int>>(
  (ref) => VideoProgressNotifier(ref.read(tutorialRepoProvider)));
