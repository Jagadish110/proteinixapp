import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../services/connectivity_service.dart';
import '../../services/daily_mission_gate.dart';
import '../../services/guest_mode.dart';
import '../../services/local_db_service.dart';
import '../../services/supabase_service.dart';
import '../../services/sync_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashState();
}

class _SplashState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred a frame: the signed-out branch below calls context.go with no
    // await before it, and initState runs inside the first build — calling
    // straight from here made that go() land mid-build and crash the Router
    // ("setState() or markNeedsBuild() called during build"). Only visible
    // once signed out, which made it look like a fresh install just broke.
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  /// Decides the first screen.
  ///
  /// The session is stored on device, so being signed in is knowable with no
  /// network. The only remote fact needed is `onboarding_complete`, and that is
  /// cached in Hive — so an offline launch routes straight into the app instead
  /// of stalling on an unroutable socket and then dumping a signed-in user back
  /// on /welcome, which is what made the app look broken without internet.
  Future<void> _route() async {
    if (!mounted) return;
    if (!SupabaseService.isLoggedIn) {
      // Someone who chose to look around first shouldn't be sent back to the
      // welcome screen on every launch — that would make "explore" a one-time
      // trip rather than a state they're in until they sign up or back out.
      context.go(GuestMode.isActive ? '/home' : '/welcome');
      return;
    }
    final uid = SupabaseService.currentUserId!;

    final cached =
        LocalDBService.isReady ? LocalDBService.getProfile(uid) : null;
    bool? onboarded = cached?.onboardingComplete;

    // Only ask the server when we have no cached answer *and* a connection to
    // ask over. Bounded either way — this must never outlast the splash.
    if (onboarded == null && ConnectivityService.isOnline) {
      try {
        final row = await SupabaseService.client
            .from('profiles')
            .select('onboarding_complete')
            .eq('id', uid)
            .maybeSingle()
            .timeout(SyncService.timeout);
        onboarded = row != null && row['onboarding_complete'] == true;
      } catch (_) {
        onboarded = null;
      }
    }

    if (!mounted) return;

    if (onboarded == null) {
      // Signed in, nothing cached, server unreachable. Onboarding is the safe
      // landing spot: it's reachable offline and won't lose data if the user
      // has in fact already completed it.
      context.go('/onboarding');
      return;
    }

    if (!onboarded) {
      context.go('/onboarding');
      return;
    }

    final showMission = await DailyMissionGate.shouldShow();
    if (!mounted) return;
    context.go(showMission ? '/daily-mission' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    // Routing kicks off in initState and is normally faster than the first
    // frame here ever gets seen; this is what's behind it while that
    // resolves. Deliberately no icon of our own here: the OS's own splash
    // (values-v31/styles.xml) already shows one, and a second Flutter-drawn
    // icon handed off from that one was showing up mid-transition looking
    // squashed or otherwise wrong — an artifact of the handoff itself, not
    // of anything this screen draws. One icon showing once is the fix.
    return const Scaffold(backgroundColor: AppColors.background);
  }
}
