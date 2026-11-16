import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/constants/api_keys.dart';

/// Wraps RevenueCat for the app's single paid plan, Proteinix Pro: unlimited
/// photo scans, voice and text logging, the AI Coach, and no ads.
///
/// RevenueCat sits on top of Google Play Billing — every purchase, renewal
/// and cancellation here is a Play subscription. Configure `premium` as the
/// entitlement identifier in the RevenueCat dashboard (the identifier is
/// internal and stays `premium`; the user-facing name is "Pro"), attached to
/// a Google Play offering with:
///
///  - a monthly package  — ₹49 / month, no trial
///  - an annual package  — ₹399 / year, with a 7-day free trial offer
///
/// Prices and the trial are set in Play Console. This class only reads them,
/// which is why the paywall can never show a price the store will not charge.
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

  /// Length in days of the free trial Play will actually grant on [package],
  /// or 0 when there is none.
  ///
  /// Read from the store product rather than hard-coded: Play only offers a
  /// trial to an account that has not used one before, so a returning
  /// subscriber gets a product with no free phase and must not be promised
  /// seven free days they will not receive.
  static int freeTrialDays(Package package) {
    final product = package.storeProduct;
    final phase = product.defaultOption?.freePhase?.billingPeriod;
    if (phase != null) return periodDays(phase.unit, phase.value);

    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0) {
      return periodDays(intro.periodUnit, intro.periodNumberOfUnits);
    }
    return 0;
  }

  static int periodDays(PeriodUnit unit, int count) => switch (unit) {
        PeriodUnit.day => count,
        PeriodUnit.week => count * 7,
        PeriodUnit.month => count * 30,
        PeriodUnit.year => count * 365,
        PeriodUnit.unknown => 0,
      };

  /// When the free trial on [info] ends, or null if the user is not in one.
  static DateTime? trialEnd(CustomerInfo info) {
    final e = info.entitlements.active[entitlementId];
    if (e == null || e.periodType != PeriodType.trial) return null;
    final raw = e.expirationDate;
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
