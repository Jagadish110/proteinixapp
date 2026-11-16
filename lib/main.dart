import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/utils/crash_log.dart';
import 'services/connectivity_service.dart';
import 'services/error_reporter.dart';
import 'services/guest_mode.dart';
import 'services/local_db_service.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/subscription_service.dart';
import 'app.dart';

/// Ceiling on any single startup step.
///
/// Startup steps that talk to the network don't fail fast when there's no
/// route — they sit on the socket until the OS times out, which is minutes.
/// Every one of them is bounded so a dead connection costs a few seconds of
/// splash screen instead of an app that never opens.
const _startupTimeout = Duration(seconds: 8);

Future<void> main() async {
  // runZonedGuarded + the handlers in CrashLog mean an unexpected throw is
  // recorded and swallowed rather than taking the whole app down.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    CrashLog.install();
    _registerAssetLicences();

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Startup must never hard-fail on one bad step, or the app dies on launch.
    //
    // dotenv and Hive don't touch each other — Hive is local storage with no
    // env-dependent config, dotenv is just a file read — so they run
    // together. This used to be a fully sequential chain of six awaits, which
    // summed every step's latency into the splash's on-screen time even
    // though most of these steps have nothing to do with one another.
    await Future.wait([
      _step('dotenv', () => dotenv.load(fileName: '.env')),
      _step('Hive init', LocalDBService.init),
      // Needed before the splash picks a route, and it only reads one bool.
      _step('Guest mode', GuestMode.restore),
    ]);

    // All three only need dotenv, not each other: Supabase restores its
    // session from disk, RevenueCat reads an API key, Notification sets up
    // local plugins and timezone data. Running them together means this
    // group costs whichever one is slowest, not their sum.
    await Future.wait([
      _step('Supabase init', SupabaseService.init),
      _step('RevenueCat init', () => SubscriptionService.instance.configure()),
      _step('Notification init', NotificationService.init),
    ]);

    // Kept sequential, after the group above: coming online here triggers an
    // outbox drain that needs a working Supabase client, so it can't start
    // until Supabase init has actually finished.
    await _step('Connectivity init', ConnectivityService.initialize);

    // Step counter permission (Android 10+). Non-fatal if declined.
    // Kept strictly sequential: permission_handler rejects a second request
    // while one is still in flight, which silently drops whichever loses the
    // race — that is why these are awaited one at a time rather than together.
    try {
      await Permission.activityRecognition.request();
    } catch (_) {}

    // Then the notification prompt, so reminders can actually be delivered
    // without the user first having to find the Reminders screen.
    //
    // Asked at most once ever (see the prefs flag inside): Android only shows
    // the system dialog on the first request anyway, and re-requesting on every
    // launch is how an app ends up in a permission loop.
    await _step('Notification permission', _askNotificationPermissionOnce);

    // Rebuilds the alarm set if a reboot, an app update, or an OEM task-killer
    // dropped it. Unawaited — ~20 platform round trips shouldn't delay launch.
    unawaited(NotificationService.restoreIfNeeded());

    runApp(const ProviderScope(child: ProteinixApp()));
  }, (error, stack) {
    // Reported rather than only logged locally: an uncaught error is the one
    // class of failure the user cannot describe back to us, because it
    // usually looks to them like the app simply stopped.
    unawaited(ErrorReporter.report('uncaught_zone_error', error, stack));
  });
}

/// Puts bundled-asset licences into the standard Flutter licence page.
///
/// The food icons are OpenMoji, which is CC BY-SA 4.0 — attribution has to
/// ship with the app, not just sit in the repo.
void _registerAssetLicences() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/icons/food/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['OpenMoji food icons'], text);
  });
}

/// Shows the Android 13+ notification prompt, once per install.
///
/// Reminders are the app's main reason to hold this permission, so it's worth
/// asking up front rather than burying it behind the Reminders screen. Guarded
/// by a flag because a prompt on every launch is both useless (Android only
/// shows the dialog once) and the shape of a permission loop.
Future<void> _askNotificationPermissionOnce() async {
  const key = 'notif_permission_asked';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(key) ?? false) return;
  await prefs.setBool(key, true);
  await NotificationService.requestNotificationPermission();
}

/// Runs one startup step, bounded and non-fatal.
Future<void> _step(String name, Future<void> Function() body) async {
  try {
    await body().timeout(_startupTimeout);
  } on TimeoutException {
    // Startup is where a production-only failure is least visible — the app
    // opens degraded and says nothing — so these go to the server too.
    await ErrorReporter.report(
        'startup_$name', 'timed out after $_startupTimeout');
  } catch (e, s) {
    await ErrorReporter.report('startup_$name', e, s);
  }
}
