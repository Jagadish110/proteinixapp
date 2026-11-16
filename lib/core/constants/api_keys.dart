import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiKeys {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get googleWebClientId =>
      dotenv.env['GOOGLE_OAUTH_WEB_CLIENT_ID'] ?? '';
  static String get googleAndroidClientId =>
      dotenv.env['GOOGLE_OAUTH_ANDROID_CLIENT_ID'] ?? '';
  static String get revenueCatAndroidApiKey =>
      dotenv.env['REVENUECAT_ANDROID_API_KEY'] ?? '';

  /// `ENFORCE_PREMIUM=true` in `.env` turns the Free / Pro split on.
  ///
  /// Off by default, so every AI feature stays open while the Play products
  /// and the RevenueCat `premium` entitlement are still being set up — with
  /// those missing the paywall can only show its "unavailable" state, which
  /// would lock the AI features behind a door with no handle.
  static bool get enforcePremium => _optional('ENFORCE_PREMIUM') == 'true';

  /// The AdMob banner unit for the home dashboard. Empty means no ads at all:
  /// the ad SDK is never initialised and no banner is ever requested.
  ///
  /// The matching *app* id is `ADMOB_APP_ID`, read from the same `.env` by
  /// `android/app/build.gradle.kts` because it has to be in the manifest.
  static String get admobBannerUnitId =>
      _optional('ADMOB_BANNER_UNIT_ID') ?? '';

  /// Reads a key that may legitimately be absent, without throwing when
  /// dotenv itself was never loaded (widget tests, a missing `.env`).
  static String? _optional(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[key]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}
