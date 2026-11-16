import 'dart:async';
import 'dart:convert';

import '../core/utils/crash_log.dart';
import '../models/local/local_blocked_app.dart';
import '../models/local/local_daily_log.dart';
import '../models/local/local_meal.dart';
import '../models/local/local_meal_routine.dart';
import '../models/local/local_pending_sync.dart';
import '../models/local/local_profile.dart';
import '../models/local/local_sleep_schedule.dart';
import '../models/local/local_weight_log.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';
import 'supabase_service.dart';

/// Moves data between Hive and Supabase. Nothing in the UI awaits it.
///
/// Push (outbox drain) and pull (refresh from server) are separate: push must
/// happen first on reconnect, otherwise a pull would overwrite local edits with
/// the stale server copy they were meant to replace.
class SyncService {
  const SyncService._();

  /// Every network call is bounded. Offline, a Supabase request doesn't fail
  /// fast — it sits on an unroutable socket until the OS gives up, which is
  /// what left the app hanging on the splash screen with no internet.
  ///
  /// Raised from 12s once the pulls were made concurrent: this is now the whole
  /// wait rather than a quarter of it, so a slower allowance costs one window
  /// instead of four. 12s was timing out repeatedly on a real 4G connection.
  static const timeout = Duration(seconds: 20);

  /// Conflict targets for upserts, matching each table's unique constraint.
  /// `daily_logs` is keyed by day rather than by id because a row created
  /// offline has no server id to match on.
  static const _conflictTargets = <String, String>{
    'daily_logs': 'user_id,date',
    'profiles': 'id',
    'meals': 'id',
    'weight_logs': 'id',
    'sleep_schedule': 'user_id',
    'blocked_apps': 'user_id,package_name',
    'meal_routines': 'id',
  };

  static bool _isSyncing = false;
  static bool get isSyncing => _isSyncing;

  static final _controller = StreamController<void>.broadcast();

  /// Fires after every drain so badges showing the pending count can refresh.
  static Stream<void> get onSyncChanged => _controller.stream;

  /// Whether a failure is just the network being the network.
  ///
  /// Timeouts, DNS misses and dropped sockets are the *expected* condition for
  /// a local-first app on a phone — nothing is lost when they happen, because
  /// the work simply runs again later. Recording them as crash entries buried
  /// the one thing Diagnostics exists for: on a real device the log came back
  /// 13 network timeouts to 1 genuine entry, so an actual bug would have been
  /// invisible in the noise.
  ///
  /// Deliberately the same predicate [LocalPendingSync.parkedByNetwork] uses,
  /// so "released automatically on reconnect" and "not worth an entry" stay
  /// exact complements. Kept separate, they drifted: `ClientException: Write
  /// failed` — a socket dropped mid-send — was auto-released by one and logged
  /// by the other, which is a guaranteed entry on every drain forever.
  static bool _isNetworkNoise(Object e) =>
      LocalPendingSync.isNetworkError(e.toString());

  // ── Push ───────────────────────────────────────────────────────────────────

  /// Drains the outbox. Safe to call at any time — returns immediately when
  /// offline, already running, or signed out.
  static Future<void> syncPendingData() async {
    if (_isSyncing) return;
    if (!LocalDBService.isReady) return;
    if (!ConnectivityService.isOnline) return;
    if (SupabaseService.currentUserId == null) return;

    // Claimed before the first `await`, not after it.
    //
    // Six callers fire this, most of them unawaited — app start, the auth
    // listener, the connectivity listener, a hydration tap. The guard above
    // only excludes a second caller if the flag is already set by the time it
    // runs, and every statement between the check and the set used to be an
    // await: two calls in the same frame both sailed through, both drained the
    // same queue entry, and both counted a failure against it. That is why
    // Diagnostics reported writes parked "after 6 attempts" when the limit is
    // five — the same outage was being charged twice per round.
    _isSyncing = true;
    try {
      // Anything parked by a dropped connection gets another chance first: we
      // are about to attempt a sync, which means the app believes it is online,
      // and that is precisely the condition those rows were waiting for.
      await LocalDBService.releaseNetworkParked();

      for (final item in LocalDBService.getPendingSync()) {
        final ok = await _push(item);
        if (!ok) {
          // Stop on the first failure rather than hammering a queue whose
          // later entries almost certainly depend on this one.
          break;
        }
      }
    } finally {
      _isSyncing = false;
      _controller.add(null);
    }
  }

  static Future<bool> _push(LocalPendingSync item) async {
    try {
      final data = jsonDecode(item.dataJson) as Map<String, dynamic>;
      final table = SupabaseService.client.from(item.table);

      switch (item.operation) {
        case 'upsert':
          await table
              .upsert(data, onConflict: _conflictTargets[item.table])
              .timeout(timeout);
        case 'insert':
          await table.insert(data).timeout(timeout);
        case 'delete':
          await table.delete().eq('id', data['id'] as Object).timeout(timeout);
        default:
          // Unknown verb — drop it rather than retry forever.
          await LocalDBService.markSynced(item.id);
          return true;
      }

      await LocalDBService.markSynced(item.id);
      return true;
    } catch (e) {
      await LocalDBService.recordSyncFailure(item, e);
      // Parked, not deleted: the write stays on disk and shows up in
      // Diagnostics. Silently discarding a user's logged meal after five
      // failed attempts is worse than carrying it.
      //
      // Only a park that will not clear itself is worth an entry, though. A
      // park caused by the network is released again by
      // [LocalDBService.releaseNetworkParked] at the top of the very next
      // drain, so recording it writes a fresh entry every cycle for as long as
      // the signal is bad. On a real device that filled all twenty slots with
      // the same daily_logs upsert — the exact noise [_isNetworkNoise] was
      // written to keep out of the pull path, which the push path never
      // applied. Nothing is lost by staying quiet: the row is still on disk,
      // still counted, and still retried.
      if (item.isParked && !_isNetworkNoise(e)) {
        await CrashLog.record(
          'Sync parked after ${item.retryCount} attempts '
          '(${item.operation} ${item.table}): $e',
          StackTrace.current,
        );
      }
      return false;
    }
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  static bool _isPulling = false;
  static DateTime? _lastPullAt;
  static String? _lastPullUid;

  /// How long a completed pull is considered fresh. The auth listener, the
  /// connectivity listener and startup can all fire within a second of each
  /// other; without this they'd each run a full four-table download.
  static const _pullFreshness = Duration(seconds: 20);

  /// Refreshes the local cache from Supabase. Silent on failure — a stale cache
  /// is a working app, and this runs on every launch.
  ///
  /// Rows land through `put…Local`, which never enqueues an outbox entry and
  /// never overwrites a local row with unsynced edits.
  ///
  /// Pass [force] for an explicit user action (pull-to-refresh), which should
  /// bypass the freshness window.
  static Future<void> pullFromSupabase(String userId,
      {bool force = false}) async {
    if (!LocalDBService.isReady) return;
    if (!ConnectivityService.isOnline) return;
    if (userId.isEmpty) return;
    if (_isPulling) return;

    if (!force &&
        _lastPullUid == userId &&
        _lastPullAt != null &&
        DateTime.now().difference(_lastPullAt!) < _pullFreshness) {
      return;
    }

    _isPulling = true;
    try {
      // In parallel, not one after another. Each carries its own [timeout], so
      // run sequentially a poor connection could spend four full timeouts —
      // most of a minute — before the dashboard saw any server data at all.
      // They touch different tables and different Hive boxes, so nothing here
      // depends on the order.
      await Future.wait([
        _pullProfile(userId),
        _pullDailyLogs(userId),
        _pullMeals(userId),
        _pullWeightLogs(userId),
        _pullRoutines(userId),
      ]);
      _lastPullAt = DateTime.now();
      _lastPullUid = userId;
    } finally {
      _isPulling = false;
      _controller.add(null);
    }
  }

  /// Records a pull failure unless it is ordinary network trouble.
  static Future<void> _recordPullFailure(
      String what, Object e, StackTrace s) async {
    if (_isNetworkNoise(e)) return;
    await CrashLog.record('$what: $e', s);
  }

  static Future<void> _pullProfile(String userId) async {
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (row == null) return;
      await LocalDBService.putProfileLocal(LocalProfile.fromRow(row));
    } catch (e, s) {
      await _recordPullFailure('Profile pull failed', e, s);
    }
  }

  static Future<void> _pullDailyLogs(String userId) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 30));
      final rows = await SupabaseService.client
          .from('daily_logs')
          .select()
          .eq('user_id', userId)
          .gte('date', LocalDailyLog.isoDate(since))
          .order('date', ascending: false)
          .timeout(timeout);
      for (final row in rows as List) {
        await LocalDBService.putDailyLogLocal(
            LocalDailyLog.fromRow(row as Map<String, dynamic>));
      }
    } catch (e, s) {
      await _recordPullFailure('Daily log pull failed', e, s);
    }
  }

  static Future<void> _pullMeals(String userId) async {
    try {
      // Same 30-day window as the logs — the Progress screen charts that range,
      // and pulling only today would leave it blank offline.
      final since = DateTime.now().subtract(const Duration(days: 30));
      final rows = await SupabaseService.client
          .from('meals')
          .select()
          .eq('user_id', userId)
          .gte('date', LocalDailyLog.isoDate(since))
          .timeout(timeout);
      for (final row in rows as List) {
        await LocalDBService.putMealLocal(
            LocalMeal.fromRow(row as Map<String, dynamic>));
      }
    } catch (e, s) {
      await _recordPullFailure('Meal pull failed', e, s);
    }
  }

  static Future<void> _pullWeightLogs(String userId) async {
    try {
      final rows = await SupabaseService.client
          .from('weight_logs')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false)
          .limit(180)
          .timeout(timeout);
      for (final row in rows as List) {
        await LocalDBService.putWeightLogLocal(
            LocalWeightLog.fromRow(row as Map<String, dynamic>));
      }
    } catch (e, s) {
      await _recordPullFailure('Weight log pull failed', e, s);
    }
  }

  static Future<void> _pullRoutines(String userId) async {
    try {
      final rows = await SupabaseService.client
          .from('meal_routines')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(timeout);
      for (final row in rows as List) {
        await LocalDBService.putRoutineLocal(
            LocalMealRoutine.fromRow(row as Map<String, dynamic>));
      }
    } catch (e, s) {
      await _recordPullFailure('Routine pull failed', e, s);
    }
  }

  /// Optional: Sleep Guard config. Kept separate because the native service
  /// owns this state at runtime and the tables may not exist on every install.
  static Future<void> pullSleepConfig(String userId) async {
    try {
      final schedule = await SupabaseService.client
          .from('sleep_schedule')
          .select()
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (schedule != null) {
        await LocalDBService.putSleepScheduleLocal(
            LocalSleepSchedule.fromRow(schedule));
      }

      final apps = await SupabaseService.client
          .from('blocked_apps')
          .select()
          .eq('user_id', userId)
          .timeout(timeout);
      for (final row in apps as List) {
        await LocalDBService.putBlockedAppLocal(
            LocalBlockedApp.fromRow(row as Map<String, dynamic>));
      }
    } catch (e, s) {
      await _recordPullFailure('Sleep config pull failed', e, s);
    }
  }

  // ── Startup ────────────────────────────────────────────────────────────────

  /// Called once the user is known: push what's queued, then refresh.
  ///
  /// Push before pull, always — the queue holds edits the server hasn't seen,
  /// and pulling first would hand back the values those edits were replacing.
  static Future<void> onAppStart(String userId) async {
    if (!ConnectivityService.isOnline) return;
    await syncPendingData();
    await pullFromSupabase(userId);
  }
}
