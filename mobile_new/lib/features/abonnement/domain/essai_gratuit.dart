import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// L'essai gratuit d'un abonnement, tel que le store le propose
/// (8 novembre 2026, d'après Sofascore : « 3 jours d'essai gratuit »).
///
/// L'offre se crée dans App Store Connect (offre d'introduction « Essai
/// gratuit ») ou dans la Play Console (offre avec une phase gratuite). Tant
/// qu'elle n'existe pas, rien ne s'affiche : la page ne promet que ce que le
/// store accordera.
enum UniteEssai { jour, semaine, mois, an }

typedef EssaiGratuit = ({int nombre, UniteEssai unite});

/// L'essai offert sur [produit], ou null.
EssaiGratuit? essaiGratuit(ProductDetails produit) {
  if (produit is AppStoreProductDetails) {
    final intro = produit.skProduct.introductoryPrice;
    if (intro == null || intro.paymentMode != SKProductDiscountPaymentMode.freeTrail) return null;
    final unite = switch (intro.subscriptionPeriod.unit) {
      SKSubscriptionPeriodUnit.day => UniteEssai.jour,
      SKSubscriptionPeriodUnit.week => UniteEssai.semaine,
      SKSubscriptionPeriodUnit.month => UniteEssai.mois,
      SKSubscriptionPeriodUnit.year => UniteEssai.an,
    };
    final nombre = intro.subscriptionPeriod.numberOfUnits * (intro.numberOfPeriods < 1 ? 1 : intro.numberOfPeriods);
    return nombre > 0 ? (nombre: nombre, unite: unite) : null;
  }
  if (produit is GooglePlayProductDetails) {
    final offres = produit.productDetails.subscriptionOfferDetails;
    final i = produit.subscriptionIndex;
    if (offres == null || i == null || i >= offres.length) return null;
    final phases = offres[i].pricingPhases;
    if (phases.isEmpty || phases.first.priceAmountMicros != 0) return null;
    return essaiDepuisPeriodeIso(phases.first.billingPeriod, cycles: phases.first.billingCycleCount);
  }
  return null;
}

/// « P3D », « P1W », « P1M » (ISO 8601, Google Play) × [cycles].
EssaiGratuit? essaiDepuisPeriodeIso(String periode, {int cycles = 1}) {
  final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(periode.trim().toUpperCase());
  if (m == null) return null;
  final nombre = int.parse(m.group(1)!) * (cycles < 1 ? 1 : cycles);
  if (nombre <= 0) return null;
  final unite = switch (m.group(2)) {
    'D' => UniteEssai.jour,
    'W' => UniteEssai.semaine,
    'M' => UniteEssai.mois,
    _ => UniteEssai.an,
  };
  return (nombre: nombre, unite: unite);
}
