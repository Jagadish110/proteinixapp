import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/constants/api_keys.dart';

/// The app's one ad placement: a single banner at the bottom of the home
/// dashboard, for users who are not on Pro.
///
/// Rules this class exists to keep:
///
///  - **One banner, one screen.** No interstitials, no rewarded or app-open
///    ads, no banners anywhere else. There is deliberately no API here for
///    any other format.
///  - **Nothing about the user goes to the ad SDK.** Every request is a bare
///    `AdRequest()` — no keywords, no content URL, no user id, no extras.
///    In particular, steps and sleep from Health Connect, and anything
///    derived from them or from the food log, must never be passed to
///    `google_mobile_ads` in any form. Google Play's Health Connect policy
///    forbids using that data for advertising, and nothing in this file
///    imports a model, provider or service that holds it. Keep it that way.
///  - **No ads without configuration.** With no `ADMOB_BANNER_UNIT_ID` in
///    `.env` the SDK is never initialised and no request is ever made.
class AdService {
  const AdService._();

  static Future<InitializationStatus>? _init;

  /// Whether a banner unit has been configured at all.
  static bool get isConfigured => ApiKeys.admobBannerUnitId.isNotEmpty;

  static String get bannerUnitId => ApiKeys.admobBannerUnitId;

  /// Starts the ad SDK once, the first time a banner is actually needed —
  /// so Pro users, and builds with no ad unit, never load it.
  static Future<void> ensureInitialized() async {
    if (!isConfigured) return;
    await (_init ??= MobileAds.instance.initialize());
  }

  /// The only request the app ever makes. See the class comment before
  /// adding a single argument to it.
  static AdRequest request() => const AdRequest();
}
