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
}
