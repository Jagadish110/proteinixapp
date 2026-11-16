import 'daily_mission_gate.dart';
import 'supabase_service.dart';

/// Where to send a user the moment they authenticate.
///
/// Shared rather than duplicated because the app now has three ways in — email
/// and password, the OAuth deep link, and the native Google account picker —
/// and each has to make the same decision about onboarding. The Google path
/// originally had no routing at all: the browser flow it replaced navigated
/// from the deep-link handler, and `signInWithIdToken` produces no deep link,
/// so a successful sign-in left the user sitting on the login screen.
Future<String> postSignInRoute() async {
  final session = SupabaseService.client.auth.currentSession;
  if (session == null) return '/welcome';

  try {
    final row = await SupabaseService.client
        .from('profiles')
        .select('onboarding_complete')
        .eq('id', session.user.id)
        .maybeSingle();

    if (row == null || row['onboarding_complete'] != true) return '/onboarding';
    return await DailyMissionGate.shouldShow() ? '/daily-mission' : '/home';
  } catch (_) {
    // Unreadable profile means we can't prove onboarding is done, and sending a
    // finished user through it again is recoverable where dropping a new user
    // straight onto an empty dashboard is not.
    return '/onboarding';
  }
}
