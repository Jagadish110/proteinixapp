import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/constants/api_keys.dart';

/// Wraps RevenueCat for the app's single "premium" entitlement, which gates
/// every Gemini-backed feature (photo/text/voice food logging + AI Coach).
///
/// One plan, not multiple tiers — with per-user AI cost this low, splitting
/// into Plus/Pro tiers just adds gating complexity and buyer hesitation
/// without a cost reason to justify it. Configure "premium" as the
/// entitlement identifier in the RevenueCat dashboard, attached to a Google
/// Play offering with a monthly and an annual package.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const entitlementId = 'premium';

  bool _configured = false;

  Future<void> configure() async {
    if (_configured) return;
    final key = ApiKeys.revenueCatAndroidApiKey;
    if (key.isEmpty) return;
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(key));
    _configured = true;
  }

  /// Ties the RevenueCat user to the signed-in Supabase account so the
  /// entitlement follows them across devices and reinstalls.
  Future<void> logIn(String supabaseUserId) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(supabaseUserId);
    } catch (_) {}
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {
      // Throws if the RevenueCat user is already anonymous — fine to ignore.
    }
  }

  Future<bool> isEntitled() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (_) {
      return false;
    }
  }

  /// The single configured offering (its packages are the monthly/annual
  /// plans shown on the paywall). Null if RevenueCat isn't configured yet or
  /// the dashboard has no current offering set.
  Future<Offering?> getOffering() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (_) {
      return null;
    }
  }

  Future<CustomerInfo> purchase(Package package) async {
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return result.customerInfo;
  }

  Future<CustomerInfo> restore() => Purchases.restorePurchases();
}
