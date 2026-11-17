import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'services/supabase_service.dart';
import 'core/constants/strings.dart';
import 'core/theme/app_theme.dart';
import 'screens/auth/email_confirmation_screen.dart';
import 'screens/auth/login_screen.dart';
import 'core/utils/entitlement_gate.dart';
import 'screens/scan/barcode_scan_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/home/daily_mission_screen.dart';
import 'screens/log/ai_log_screen.dart';
import 'screens/log/log_food_screen.dart';
import 'screens/log/voice_log_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/profile/diagnostics_screen.dart';
import 'screens/profile/notification_settings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/support_screen.dart';
import 'screens/scan/food_scanner_screen.dart';
import 'screens/sleep/sleep_screen.dart';
import 'services/meal_schedule_service.dart';
import 'screens/subscription/paywall_screen.dart';
import 'screens/subscription/subscription_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/daily_log_provider.dart';
import 'services/connectivity_service.dart';
import 'services/auth_routing.dart';
import 'services/notification_service.dart';
import 'services/pedometer_service.dart';
import 'services/sleep_tracking_service.dart';
import 'services/subscription_service.dart';
import 'services/sync_service.dart';

class ProteinixApp extends ConsumerStatefulWidget {
  const ProteinixApp({super.key});

  @override
  ConsumerState<ProteinixApp> createState() => _ProteinixAppState();
}

class _ProteinixAppState extends ConsumerState<ProteinixApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<String>? _notificationSub;
  StreamSubscription<bool>? _onlineSub;
  late final GoRouter _router;

  /// Drains the outbox, refreshes the cache, then tells the local-first
  /// providers to re-read Hive.
  ///
  /// Triggered from the auth stream rather than once in [initState]. Supabase
  /// restores the persisted session *asynchronously*, so a one-shot read of
  /// `currentUser` at startup is usually still null — the pull never ran, Hive
  /// stayed empty, and Meals/Nutrition/Progress had nothing to render even
  /// though the account had plenty of data on the server.
  Future<void> _syncOnStart(String uid) async {
    if (uid.isEmpty) return;
    await SyncService.onAppStart(uid);
    if (!mounted) return;
    ref.read(dataRevisionProvider.notifier).state++;
    await ref.read(profileProvider.notifier).load();
    if (!mounted) return;

    // Step counting starts with the session, not with the Home screen.
    //
    // [PedometerService.start] was only ever called from Home's refresh, so a
    // launch that landed anywhere else subscribed to nothing: the daily
    // mission screen after a fresh sign-in, a tapped reminder opening
    // /log-food, the sleep screen from a morning report. The ring showed
    // whatever was last stored until Home was reached, which made step
    // tracking look like something the user had to press a button to begin —
    // and in effect it was.
    //
    // Idempotent by design: the sensor subscription is created once and
    // Home's own call only refreshes the stride figures afterwards.
    final profile = ref.read(profileProvider).value;
    unawaited(PedometerService().start(
      weightKg: profile?.weightKg ?? 70.0,
      heightCm: profile?.heightCm ?? 170.0,
      gender: profile?.gender ?? 'male',
    ));
  }

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
        GoRoute(
          path: '/confirm-email',
          builder: (_, state) =>
              EmailConfirmationScreen(email: state.extra as String? ?? ''),
        ),
        GoRoute(
            path: '/onboarding',
            builder: (_, state) =>
                OnboardingScreen(isEditing: state.extra as bool? ?? false)),
        GoRoute(path: '/home', builder: (_, __) => const MainNavigation()),
        GoRoute(
            path: '/daily-mission',
            builder: (_, __) => const DailyMissionScreen()),
        GoRoute(
          path: '/log-food',
          builder: (_, state) =>
              LogFoodScreen(initialMealType: state.extra as String?),
          routes: [
            GoRoute(
              path: 'ai',
              builder: (_, state) =>
                  AiLogScreen(mealType: state.extra as String? ?? 'snack'),
            ),
            GoRoute(
              path: 'voice',
              builder: (_, state) =>
                  VoiceLogScreen(mealType: state.extra as String? ?? 'snack'),
            ),
          ],
        ),
        GoRoute(
          path: '/scan',
          builder: (_, state) =>
              FoodScannerScreen(mealType: state.extra as String?),
        ),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(
          path: '/paywall',
          builder: (_, state) =>
              PaywallScreen(feature: state.extra as ProFeature?),
        ),
        GoRoute(
          path: '/barcode',
          builder: (_, state) =>
              BarcodeScanScreen(mealType: state.extra as String?),
        ),
        GoRoute(
            path: '/subscription',
            builder: (_, __) => const SubscriptionScreen()),
        GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationSettingsScreen()),
        GoRoute(
            path: '/diagnostics',
            builder: (_, __) => const DiagnosticsScreen()),
        GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
        GoRoute(path: '/sleep', builder: (_, __) => const SleepScreen()),
      ],
    );

    // OAuth and email-confirmation callbacks land here — same deep link
    // scheme for both. Warm links (app already running) arrive via the
    // stream; a cold start (app fully closed, e.g. user backed out after
    // signup and tapped the email link later) needs its initial link
    // fetched separately since it happened before this listener existed.
    _appLinks = AppLinks();
    _linkSub = _appLinks.uriLinkStream.listen(_handleAuthDeepLink);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleAuthDeepLink(uri);
    });

    // Reminder taps. A cold start also has to replay the payload the app was
    // launched with — the stream only carries taps that happen while the
    // engine is already alive.
    _notificationSub = NotificationService.taps.listen(_handleNotificationTap);

    // Push anything queued from a previous offline session, then refresh the
    // cache. The auth listener in build() is the reliable trigger; this covers
    // the case where the session was already restored before we subscribed.
    final uid = SupabaseService.currentUserId;
    if (uid != null) unawaited(_syncOnStart(uid));

    // A reconnect mid-session flushes the queue (ConnectivityService does that)
    // and then needs the screens to repaint with whatever came back.
    _onlineSub = ConnectivityService.onStatusChange.listen((online) {
      if (!online) return;
      final id = SupabaseService.currentUserId;
      if (id != null) unawaited(_syncOnStart(id));
    });
    final launch = NotificationService.launchPayload;
    if (launch != null) {
      NotificationService.launchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleNotificationTap(launch),
      );
    }

    // The morning sleep report takes a different path to every other reminder.
    // It is posted from a BroadcastReceiver at the wake time, with no Flutter
    // engine alive to hold a payload, so it hands its destination over as an
    // Intent extra that only becomes readable once Dart is running.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainLaunchRoute());
  }

  Future<void> _drainLaunchRoute() async {
    final route = await SleepTrackingService.consumeLaunchRoute();
    if (route == null || !mounted) return;
    if (!SupabaseService.isLoggedIn) return;
    _router.go(route);
  }

  /// Routes a tapped reminder. Payloads look like `water`, `step`, `sleep` or
  /// `meal:lunch`, optionally suffixed `#log_meal` / `#skip_meal` when an
  /// action button was used.
  Future<void> _handleNotificationTap(String payload) async {
    // Never yank a signed-out user out of the auth flow.
    if (!SupabaseService.isLoggedIn) return;

    final hash = payload.indexOf('#');
    final action = hash == -1 ? null : payload.substring(hash + 1);
    final target = hash == -1 ? payload : payload.substring(0, hash);

    if (action == 'skip_meal') return; // dismissal only

    if (target.startsWith('meal:')) {
      // Reminder payloads carry the slot key. Anything unrecognised (a slot
      // deleted since the notification was scheduled) falls through to the
      // picker's own default rather than a hard-coded 'snack'.
      final key = target.substring('meal:'.length).toLowerCase();
      final slots = await MealScheduleService.load();
      final known = slots.any((s) => s.key == key);
      _router.go('/log-food', extra: known ? key : null);
      return;
    }
    if (target == 'sleep') {
      _router.go('/sleep');
      return;
    }
    // The "your free trial ends soon" reminder. Lands on the screen with the
    // cancel button, since deciding whether to keep Pro is what it is about.
    if (target == 'subscription') {
      _router.go('/home');
      unawaited(_router.push('/subscription'));
      return;
    }
    // The "finish setting up" nudge. Straight back into the wizard, which
    // restores the saved draft and lands on the step that was abandoned.
    if (target == 'onboarding') {
      _router.go('/onboarding');
      return;
    }
    _router.go('/home');
  }

  Future<void> _handleAuthDeepLink(Uri uri) async {
    // Give Supabase a moment to exchange the code in the URL for a session.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!SupabaseService.isLoggedIn) return;

    // Same rule as the login and signup screens — see [postSignInRoute].
    final route = await postSignInRoute();
    if (mounted) _router.go(route);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _notificationSub?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep RevenueCat's user identity in sync with Supabase auth so the
    // "premium" entitlement follows the account, not the device.
    ref.listen(authStateProvider, (previous, next) {
      final session = next.value?.session;
      if (session != null) {
        SubscriptionService.instance.logIn(session.user.id);
        // The moment a user actually exists — restored session on cold start,
        // or a fresh sign-in — fill the local database. This is the trigger
        // that startup's one-shot `currentUser` read kept missing.
        unawaited(_syncOnStart(session.user.id));
        // And arm the reminders, which is only permitted now that there is an
        // account. main.dart's launch-time restore runs before Supabase has
        // finished restoring the session, so it sees a signed-out app and
        // correctly does nothing — this is the call that actually lands.
        unawaited(NotificationService.restoreIfNeeded());
      } else if (next.hasValue) {
        SubscriptionService.instance.logOut();
        // Reminders belong to the account that set them. Leaving them armed
        // after a sign-out is how a signed-out phone kept nudging about meals
        // and water for data it could no longer show.
        unawaited(NotificationService.cancelReminders());
      }
    });

    return MaterialApp.router(
      title: AppStrings.appFullName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
