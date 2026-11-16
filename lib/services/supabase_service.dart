import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/api_keys.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: ApiKeys.supabaseUrl,
      publishableKey: ApiKeys.supabaseAnonKey,
    );
  }

  /// Null-safe even before [init] has run.
  ///
  /// `Supabase.instance` throws if it's touched before initialisation, and
  /// startup now brings connectivity up first — a network event arriving in
  /// that window would otherwise take down the sync layer with an assertion
  /// rather than a null.
  static User? get currentUser {
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static String? get currentUserId => currentUser?.id;
  static bool get isLoggedIn => currentUser != null;
}
