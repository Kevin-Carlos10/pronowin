import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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
/// Sur un build store, le prix du catalogue dès qu'il est chargé : celui que
/// l'acheteur paiera, dans la devise de son pays. Avant, le tarif publié par
/// le serveur.
String premiumMonthlyPriceLabel(WidgetRef ref, Map<String, dynamic>? sub) {
  final store = ref.watch(isStoreBuildProvider);
  if (store) {
    for (final p in ref.watch(iapProductsProvider)) {
      if (p is ProductDetails && p.id == 'com.pronowin.premium.monthly') return p.price;
    }
  }
  final key = store ? 'premium_price_monthly_store_usd' : 'premium_price_monthly_usd';
  final fallback = store ? 14.99 : 10.0;
  return montantAccrocheUsd((sub?[key] as num?) ?? fallback);
}

/// « $10 » pour un montant rond, « $14.99 » sinon.
///
/// Arrondi au dollar, l'accroche annonçait « $15 » pour un abonnement que
/// l'App Store facture 14,99 $ : deux prix pour la même chose.
String montantAccrocheUsd(num montant) => montant == montant.roundToDouble()
    ? '\$${montant.toStringAsFixed(0)}'
    : '\$${montant.toStringAsFixed(2)}';
