import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'storage_service.dart';

/// "Remove Ads" non-consumable purchase.
/// Create a managed product with this id in Google Play Console.
class IapService {
  static const removeAdsId = 'remove_ads';

  final StorageService storage;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? product;

  IapService(this.storage);

  Future<void> init() async {
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    final res = await _iap.queryProductDetails({removeAdsId});
    if (res.productDetails.isNotEmpty) product = res.productDetails.first;
  }

  Future<bool> buyRemoveAds() async {
    final p = product;
    if (p == null) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: p),
    );
  }

  Future<void> restore() => _iap.restorePurchases();

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.productID == removeAdsId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored)) {
        storage.setAdsRemoved(true);
      }
      if (p.pendingCompletePurchase) _iap.completePurchase(p);
    }
  }

  void dispose() => _sub?.cancel();
}
