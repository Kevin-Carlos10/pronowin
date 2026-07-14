import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stocke l'heure du dernier fetch réseau réussi par clé de cache.
/// Les providers appellent [notifier.markSynced(key)] après chaque succès réseau.
class CacheMetaNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => {};

  void markSynced(String key) {
    state = {...state, key: DateTime.now()};
  }

  DateTime? lastSync(String key) => state[key];
}

final cacheMetaProvider =
    NotifierProvider<CacheMetaNotifier, Map<String, DateTime>>(
  CacheMetaNotifier.new,
);
