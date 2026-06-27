import 'package:flutter/foundation.dart';

/// Result of a premium-unlock attempt.
enum PremiumPurchaseResult {
  /// The purchase completed and the entitlement was granted.
  purchased,

  /// The user cancelled the purchase flow.
  cancelled,

  /// In-app purchases are not wired up / unavailable on this build.
  unavailable,

  /// The purchase failed for another reason.
  error,
}

/// Premium entitlement / in-app purchase gateway for the premium theme pack.
///
/// This is intentionally a thin SCAFFOLD. There is no real StoreKit /
/// `in_app_purchase` integration yet. Wire it up before shipping by:
///   1. Adding the `in_app_purchase` package to pubspec.yaml.
///   2. Creating a non-consumable product (e.g. `premium_theme_pack`) in
///      App Store Connect / Google Play.
///   3. Implementing [purchasePremium] and [restorePurchases] against
///      `InAppPurchase.instance` (buyNonConsumable / restorePurchases) and
///      verifying the receipt before granting the entitlement.
///   4. Persisting the granted entitlement via
///      `userPrefsProvider.notifier.setPremiumUnlocked(true)`.
class PremiumService {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  /// The store product id for the premium theme pack (non-consumable).
  static const productId = 'premium_theme_pack';

  /// Display price shown in the paywall until a real store price is fetched.
  static const fallbackPriceLabel = r'$4.99';

  /// Whether a real in-app purchase backend is available.
  ///
  /// Returns false until the steps in the class doc are completed, so the
  /// paywall can show an honest "coming soon" state instead of a dead button.
  bool get isStoreAvailable => false;

  /// Attempt to purchase the premium theme pack.
  ///
  // TODO(premium): Replace with a real `in_app_purchase` flow:
  //   await InAppPurchase.instance.buyNonConsumable(purchaseParam: ...);
  //   then verify the receipt and return [PremiumPurchaseResult.purchased].
  Future<PremiumPurchaseResult> purchasePremium() async {
    if (!isStoreAvailable) return PremiumPurchaseResult.unavailable;
    return PremiumPurchaseResult.error;
  }

  /// Restore a previously purchased entitlement.
  ///
  // TODO(premium): call InAppPurchase.instance.restorePurchases() and grant
  // the entitlement if a valid receipt for [productId] is found.
  Future<PremiumPurchaseResult> restorePurchases() async {
    if (!isStoreAvailable) return PremiumPurchaseResult.unavailable;
    return PremiumPurchaseResult.error;
  }

  /// Debug-only local unlock so the premium themes can be previewed during
  /// development before the store is wired up. Never available in release.
  bool get canDevUnlock => kDebugMode;
}
