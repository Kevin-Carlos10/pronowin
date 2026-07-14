import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dio_client.dart';
import 'connectivity_provider.dart';

/// Wrapper Dio qui injecte automatiquement `extra['offline']`
/// selon l'état de la connectivité. Utiliser ce provider au lieu
/// de [dioProvider] dans tous les providers qui veulent le cache.
final offlineDioProvider = Provider<_OfflineDio>((ref) {
  final dio      = ref.watch(dioProvider);
  final isOnline = ref.watch(isOnlineProvider);
  return _OfflineDio(dio: dio, isOnline: isOnline);
});

class _OfflineDio {
  final Dio dio;
  final bool isOnline;
  const _OfflineDio({required this.dio, required this.isOnline});

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    final merged = (options ?? Options()).copyWith(
      extra: {...?options?.extra, 'offline': !isOnline},
    );
    return dio.get<T>(path, queryParameters: queryParameters, options: merged);
  }
}
