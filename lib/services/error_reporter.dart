import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/constants/strings.dart';
import '../core/utils/crash_log.dart';
import 'supabase_service.dart';

/// Ships errors to `error_logs` so production failures are visible without
/// asking the user to read a Diagnostics screen back over the phone.
///
/// Paired with [CrashLog], not a replacement for it: the local log is what
/// works offline and on a device you can't query, this is what aggregates
/// across every install. Reporting here is always best-effort — a reporter
/// that can throw, block a tap, or retry forever is worse than no reporter.
class ErrorReporter {
  const ErrorReporter._();

  /// Errors identical to one already sent this session are dropped.
  ///
  /// A failing call inside a rebuild or a resume loop can fire hundreds of
  /// times a minute; without this the table fills with the same row and the
  /// signal is buried in its own repetition.
  static final _seen = <String>{};
  static const _maxDistinctPerSession = 50;

  /// Records an error locally, then tries to push it to the server.
  ///
  /// [context] is the action that failed — `save_profile`, `log_meal` — and
  /// is what makes a row triageable at a glance.
  static Future<void> report(
    String context,
    Object error, [
    StackTrace? stack,
  ]) async {
    final message = error.toString();

    // Local first, and unconditionally: this is the copy that survives with
    // no network, and it must not depend on the upload below succeeding.
    await CrashLog.record('[$context] $message', stack);

    if (_seen.length >= _maxDistinctPerSession) return;
    final fingerprint = '$context|$message';
    if (!_seen.add(fingerprint)) return;

    // Fire-and-forget. Awaiting would put a network round trip in front of
    // the error dialog the user is waiting on.
    unawaited(_push(context, message, stack));
  }

  static Future<void> _push(
    String context,
    String message,
    StackTrace? stack,
  ) async {
    // Deliberately not gated on ConnectivityService.isOnline. That flag reads
    // false until the connectivity check finishes during startup, so gating on
    // it would drop precisely the startup failures this exists to catch. The
    // timeout and the per-session cap bound the cost of trying while offline,
    // and a genuinely offline attempt fails on DNS almost immediately.
    //
    // Errors raised with no connection are not queued for later — they stay in
    // the on-device CrashLog, readable from Diagnostics. Persisting an upload
    // queue for diagnostics would mean a failing app writing more to disk on
    // every failure, which is the wrong trade.
    try {
      await SupabaseService.client.from('error_logs').insert({
        // Null when signed out, which the anon insert policy allows —
        // a failed sign-in is precisely the error worth keeping.
        'user_id': SupabaseService.currentUserId,
        'context': context,
        'message': _clamp(message, 2000),
        // Eight frames is enough to name the call path; whole traces are
        // mostly framework noise and make rows unreadable in the dashboard.
        'stack': stack == null
            ? null
            : _clamp(stack.toString().split('\n').take(8).join('\n'), 4000),
        'app_version': AppStrings.appVersion,
        'platform': _platform(),
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Swallowed on purpose. The local copy is already written, and an
      // error reporter that reports its own failures is a loop.
    }
  }

  static String _clamp(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  static String _platform() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return kIsWeb ? 'web' : 'unknown';
    }
  }
}
