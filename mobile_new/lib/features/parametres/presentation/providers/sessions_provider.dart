import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SessionAppareil {
  final String id;
  final String? plateforme;
  final bool actuelle;
  final DateTime? debut, derniereActivite;
  const SessionAppareil({
    required this.id,
    this.plateforme,
    this.actuelle = false,
    this.debut,
    this.derniereActivite,
  });
  factory SessionAppareil.fromJson(Map<String, dynamic> j) => SessionAppareil(
    id: j['id'] as String,
    plateforme: j['platform'] as String?,
    actuelle: j['current'] == true,
    debut: DateTime.tryParse(j['startedAt'] as String? ?? '')?.toLocal(),
    derniereActivite: DateTime.tryParse(
      j['lastSeenAt'] as String? ?? '',
    )?.toLocal(),
  );
}

final sessionsAppareilsProvider =
    FutureProvider.autoDispose<List<SessionAppareil>>((ref) async {
      // Une déconnexion ou un changement de compte efface la liste affichée.
      final auth = ref.watch(authProvider);
      if (auth is AuthInitial) return const [];
      final dio = ref.watch(dioProvider);
      final stockage = ref.watch(secureStorageProvider);
      final token = await stockage.read(AppConstants.refreshTokenKey);
      final response = await dio.post(
        '/auth/sessions',
        data: {if (token != null && token.isNotEmpty) 'refresh_token': token},
      );
      final liste = (response.data as Map<String, dynamic>)['sessions'] as List;
      return liste
          .map((j) => SessionAppareil.fromJson(j as Map<String, dynamic>))
          .toList();
    });
