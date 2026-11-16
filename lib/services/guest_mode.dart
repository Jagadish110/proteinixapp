import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Lets someone look around the app before committing to an account.
///
/// Browsing is free; *writing* is not. Every screen renders normally with
/// empty data — there is no signed-in user, so the local database has nothing
/// for it — and each action that would create data asks for an account first
/// (see `requireAccount`).
///
/// Deliberately a flag rather than an anonymous Supabase session. A real
/// session would mean rows owned by a throwaway user, and then either an
/// orphaned account per curious visitor or a migration path to move that data
/// onto the real one. Neither is worth it for what is a preview of the UI.
class GuestMode {
  const GuestMode._();

  static const _prefsKey = 'guest_mode_active';

  /// Mirrors the stored flag so routing can read it without awaiting.
  ///
  /// The splash screen decides the first route inside a frame callback, and a
  /// disk read there would either stall that frame or force the decision to
  /// happen after the first screen had already been chosen.
  static bool _active = false;

  static bool get isActive => _active;

  /// True when the app is being used without an account.
  ///
  /// Signing in doesn't need to clear the flag for this to become false —
  /// a real session always wins — which keeps the two states from ever
  /// disagreeing if a sign-in races the write below.
  static bool get isGuest => _active && !SupabaseService.isLoggedIn;

  /// Loads the stored flag. Called once at startup, before routing.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _active = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      _active = false;
    }
  }

  static Future<void> enable() async {
    _active = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {
      // In-memory flag still holds for this session.
    }
  }

  /// Ends guest mode — on sign-in, or when the user backs out to the
  /// welcome screen.
  static Future<void> disable() async {
    _active = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
