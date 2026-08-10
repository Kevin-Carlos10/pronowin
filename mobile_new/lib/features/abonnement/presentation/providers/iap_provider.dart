import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../data/iap_service.dart';

final iapServiceProvider = Provider<IapService>((ref) {
  final svc = IapService(ref.read(dioProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

/// Initialise le service et expose sa disponibilité.
///
/// Peut être `false` légitimement : store indisponible, appareil sans Play
/// Services, achats restreints par le contrôle parental. Le paywall doit
/// alors afficher un message, pas une page vide.
final iapReadyProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(isStoreBuildProvider)) return false;
  return ref.read(iapServiceProvider).init();
});

/// Produits chargés depuis le store (prix localisés inclus).
final iapProductsProvider = Provider<List<dynamic>>((ref) {
  final ready = ref.watch(iapReadyProvider).value ?? false;
  if (!ready) return const [];
  return ref.read(iapServiceProvider).products;
});

/// Prix mensuel à afficher sur les écrans d'accroche (« à partir de X »).
///
/// Sur un build store, le tarif est majoré de 50 % pour absorber la commission
/// Apple/Google : afficher le prix Mobile Money y annoncerait un montant
/// inférieur à celui réellement débité au moment de payer.
///
/// Le prix ferme reste celui que le store renvoie sur l'écran d'achat — cette
/// valeur ne sert qu'à l'accroche, avant que les produits ne soient chargés.
String premiumMonthlyPriceLabel(WidgetRef ref, Map<String, dynamic>? sub) {
  final key = ref.watch(isStoreBuildProvider)
    ? 'premium_price_monthly_store_usd'
    : 'premium_price_monthly_usd';
  final fallback = ref.watch(isStoreBuildProvider) ? 15.0 : 10.0;
  final v = (sub?[key] as num?)?.toDouble() ?? fallback;
  return '\$${v.toStringAsFixed(0)}';
}
