import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../../domain/entities/tutorial_entity.dart';
import '../models/tutorial_model.dart';

abstract class TutorialRemoteDataSource {
  Future<List<TutorialModel>> getTutorials({TutorialLevel? level, TutorialCategory? category});
  Future<TutorialModel>       getTutorialDetail(String id);
  Future<void>                markProgress(String id, int watchedSeconds, bool completed);
  Future<List<TutorialModel>> getProgress();
}

class TutorialRemoteDataSourceImpl implements TutorialRemoteDataSource {
  final Dio _dio;
  TutorialRemoteDataSourceImpl(this._dio);

  @override
  Future<List<TutorialModel>> getTutorials({TutorialLevel? level, TutorialCategory? category}) async {
    try {
      final r = await _dio.get(ApiEndpoints.tutorials, queryParameters: {
        if (level    != null) 'level':    level.name,
        if (category != null) 'category': category.name,
      });
      return (r.data as List).map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<TutorialModel> getTutorialDetail(String id) async {
    try {
      final r = await _dio.get('${ApiEndpoints.tutorials}/$id');
      return TutorialModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<void> markProgress(String id, int watchedSeconds, bool completed) async {
    try {
      await _dio.post('${ApiEndpoints.tutorials}/$id/progress', data: {
        'watched_seconds': watchedSeconds, 'completed': completed,
      });
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<List<TutorialModel>> getProgress() async {
    try {
      final r = await _dio.get('${ApiEndpoints.tutorials}/progress');
      return (r.data as List).map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) { throw _handle(e); }
  }

  Failure _handle(DioException e, [String? ctx]) =>
      handleDioException(e, context: ctx);
}
