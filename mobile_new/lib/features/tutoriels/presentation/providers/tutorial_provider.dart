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
  final TutorialLevel? level;
  final String?        category;
  const TutorialFilter({this.level, this.category});
  TutorialFilter copyWith({TutorialLevel? level, String? category, bool clearLevel = false, bool clearCategory = false}) =>
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

  /// Enregistre la progression. Rend `true` si le serveur l'a bien reçue.
  ///
  /// Le résultat `Either` de l'enregistrement était jeté : un échec réseau
  /// passait pour une réussite, et l'écran affichait « Tutoriel marqué comme
  /// terminé ! » sur une progression que personne n'avait enregistrée. Au
  /// lancement suivant, la coche avait disparu sans explication.
  ///
  /// L'état local reste posé d'abord — l'écran doit répondre au doigt — mais
  /// l'appelant sait désormais s'il peut l'annoncer.
  Future<bool> updateProgress(String tutorialId, int seconds, bool completed) async {
    state = {...state, tutorialId: seconds};
    final r = await MarkProgressUseCase(_repo).call(tutorialId, seconds, completed);
    return r.isRight();
  }
}

final videoProgressProvider = StateNotifierProvider<VideoProgressNotifier, Map<String, int>>(
  (ref) => VideoProgressNotifier(ref.read(tutorialRepoProvider)));
