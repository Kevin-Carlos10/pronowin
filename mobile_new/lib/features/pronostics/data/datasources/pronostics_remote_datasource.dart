import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../models/match_model.dart';
import '../models/league_model.dart';

class MatchesPage {
  final List<MatchModel> data;
  final String? nextCursor;
  final bool hasMore;
  const MatchesPage({required this.data, this.nextCursor, required this.hasMore});
}

abstract class PronosticsRemoteDataSource {
  Future<MatchesPage>       getMatches({String? leagueId, String? dateFilter, String? sport, String? cursor, int limit});
  Future<MatchModel>        getMatchDetail(String matchId);
  Future<List<LeagueModel>> getLeagues();
}

class PronosticsRemoteDataSourceImpl implements PronosticsRemoteDataSource {
  final Dio _dio;
  PronosticsRemoteDataSourceImpl(this._dio);

  @override
  Future<MatchesPage> getMatches({
    String? leagueId,
    String? dateFilter,
    String? sport,
    String? cursor,
    int     limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.pronostics,
        queryParameters: {
          if (leagueId   != null) 'league_id':   leagueId,
          if (dateFilter != null) 'date_filter': dateFilter,
          if (sport      != null) 'sport':       sport,
          if (cursor     != null) 'cursor':      cursor,
          'limit':       limit,
          'include_all': 'true',
        },
      );
      final body = response.data as Map<String, dynamic>;
      final list = body['data'] as List<dynamic>;
      return MatchesPage(
        data:       list.map((e) => MatchModel.fromJson(e as Map<String, dynamic>)).toList(),
        nextCursor: body['nextCursor'] as String?,
        hasMore:    body['hasMore']    as bool? ?? false,
      );
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  @override
  Future<MatchModel> getMatchDetail(String matchId) async {
    try {
      final response = await _dio.get('${ApiEndpoints.pronostics}/$matchId');
      return MatchModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  @override
  Future<List<LeagueModel>> getLeagues() async {
    try {
      final response = await _dio.get(ApiEndpoints.leagues);
      final list = response.data as List<dynamic>;
      return list.map((e) => LeagueModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  Failure _handle(DioException e, [String? ctx]) =>
      handleDioException(e, context: ctx);
}
