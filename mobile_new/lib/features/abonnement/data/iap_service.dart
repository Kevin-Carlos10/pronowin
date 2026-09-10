import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Identifiants produits — doivent correspondre exactement à ceux créés dans
/// App Store Connect et la Play Console, et à `IAP_PRODUCTS` côté backend.
/// Le backend les expose sur `/subscriptions/iap/products` : on les récupère
/// plutôt que de les figer ici, pour ne pas avoir trois sources de vérité.
const kIapFallbackProductIds = <String>{
  'com.pronowin.premium.monthly',
  'com.pronowin.premium.annual',
};

/// Résultat d'une tentative d'achat, tel que l'UI a besoin de le connaître.
sealed class IapResult {
  const IapResult();
}

class IapSuccess extends IapResult {
  final DateTime expiresAt;
  const IapSuccess(this.expiresAt);
}

class IapCancelled extends IapResult {
  const IapCancelled();
}

class IapFailure extends IapResult {
  final String message;
  const IapFailure(this.message);
}

/// Achat intégré App Store / Google Play.
///
/// Le reçu n'est jamais interprété côté client : il est transmis au backend,
/// qui interroge le store. Un client peut mentir, le store non.
class IapService {
  IapService(this._dio);

  final Dio _dio;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _results = StreamController<IapResult>.broadcast();

  /// Émet le résultat de chaque achat validé par le backend.
  Stream<IapResult> get results => _results.stream;

  List<ProductDetails> _products = const [];
  List<ProductDetails> get products => _products;

  bool _ready = false;
  bool get isReady => _ready;

  /// À appeler une fois au démarrage du paywall.
  ///
  /// Le flux d'achat doit être écouté **avant** tout achat : sur iOS, une
  /// transaction interrompue (crash, coupure réseau) est rejouée par StoreKit
  /// dès l'abonnement au flux, et il faut pouvoir la finaliser.
  Future<bool> init() async {
    if (_ready) return true;
    if (!await _iap.isAvailable()) return false;

    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _results.add(IapFailure('$e')),
    );

    await _loadProducts();
    _ready = true;
    return true;
  }

  Future<void> _loadProducts() async {
    Set<String> ids = kIapFallbackProductIds;
    try {
      final r = await _dio.get('/subscriptions/iap/products');
      final list = (r.data['product_ids'] as List?)?.cast<String>();
      if (list != null && list.isNotEmpty) ids = list.toSet();
    } catch (_) {
      // Backend injoignable : on retombe sur la liste locale plutôt que de
      // présenter un paywall vide.
    }

    final resp = await _iap.queryProductDetails(ids);
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] Produits introuvables sur le store : ${resp.notFoundIDs}');
    }
    _products = resp.productDetails;
  }

  ProductDetails? productFor(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Lance l'achat. Le résultat arrive sur [results], pas en retour :
  /// l'utilisateur peut fermer l'app pendant la transaction et celle-ci
  /// aboutira quand même.
  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Exigé par Apple : tout achat non consommable doit pouvoir être restauré.
  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          break;

        case PurchaseStatus.canceled:
          _results.add(const IapCancelled());

        case PurchaseStatus.error:
          _results.add(IapFailure(p.error?.message ?? 'Achat échoué.'));

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
      }

      // Toujours finaliser, y compris en erreur : une transaction non
      // finalisée est resoumise indéfiniment par StoreKit à chaque lancement.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    final receipt = p.verificationData.serverVerificationData;
    if (receipt.isEmpty) {
      _results.add(const IapFailure('Reçu vide.'));
      return;
    }

    try {
      final r = await _dio.post('/subscriptions/iap/verify', data: {
        'store':   Platform.isIOS ? 'apple' : 'google',
        'receipt': receipt,
      });
      final expires = r.data['expires_at'] as String?;
      if (r.data['active'] == true && expires != null) {
        _results.add(IapSuccess(DateTime.parse(expires)));
      } else {
        _results.add(IapFailure(
          'Abonnement inactif (statut : ${r.data['status'] ?? 'inconnu'}).'));
      }
    } catch (e) {
      // L'achat est encaissé par le store mais notre serveur n'a pas pu le
      // valider. Ne surtout pas le présenter comme un échec définitif : la
      // restauration au prochain lancement le rattrapera.
      _results.add(const IapFailure(
        'Paiement reçu, activation en attente. Rouvre l\'app dans un instant '
        'ou touche « Restaurer mes achats ».'));
    }
  }

  /// Page de gestion de l'abonnement du store (résiliation, changement de
  /// plan). Apple et Google imposent que l'app y donne accès depuis l'écran
  /// d'abonnement.
  static Uri manageSubscriptionsUrl({String? androidPackage, String? productId}) {
    if (Platform.isIOS) {
      return Uri.parse('https://apps.apple.com/account/subscriptions');
    }
    final q = <String, String>{
      'sku':     ?productId,
      'package': ?androidPackage,
    };
    return Uri.https('play.google.com', '/store/account/subscriptions',
        q.isEmpty ? null : q);
  }

  void dispose() {
    _sub?.cancel();
    _results.close();
  }
}
