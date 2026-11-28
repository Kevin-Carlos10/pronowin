
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pronowin/features/abonnement/data/iap_service.dart';

class StoreDeTest extends InAppPurchasePlatform {
  final achats = <PurchaseParam>[];
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    achats.add(purchaseParam);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final produit = ProductDetails(id: 'premium', title: 'Premium',
    description: '', price: '10', rawPrice: 10, currencyCode: 'USD');
  late StoreDeTest store;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    // Initialiser avant d'installer le faux store, sans enregistrer Android/iOS.
    InAppPurchase.instance;
    store = StoreDeTest();
    InAppPurchasePlatform.instance = store;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('le compte courant est relu avant chaque achat, sans réutiliser le précédent', () async {
    var compte = 'compte-a';
    var demandes = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      expect(r.method, 'POST');
      expect(r.path, '/subscriptions/iap/purchase-context');
      demandes++;
      h.resolve(Response(requestOptions: r, data: {'google': compte, 'apple': compte}));
    }));
    final service = IapService(dio);
    await service.buy(produit);
    compte = 'compte-b';
    await service.buy(produit);
    expect(demandes, 2);
    expect(store.achats.map((p) => p.applicationUserName), ['compte-a','compte-b']);
    service.dispose();
  });

  test('serveur indisponible : aucun paiement lancé', () async {
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.reject(DioException(requestOptions: r, type: DioExceptionType.connectionError));
    }));
    final service = IapService(dio);
    await expectLater(service.buy(produit), throwsA(isA<DioException>()));
    expect(store.achats, isEmpty);
    service.dispose();
  });

  test('identifiant absent : aucun paiement lancé', () async {
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, data: <String, Object>{}));
    }));
    final service = IapService(dio);
    await expectLater(service.buy(produit), throwsA(isA<StateError>()));
    expect(store.achats, isEmpty);
    service.dispose();
  });
}
