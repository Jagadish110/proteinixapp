import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/crash_log.dart';
import '../models/local/local_blocked_app.dart';
import '../models/local/local_daily_log.dart';
import '../models/local/local_meal.dart';
import '../models/local/local_meal_routine.dart';
import '../models/local/local_pending_sync.dart';
import '../models/local/local_profile.dart';
import '../models/local/local_sleep_schedule.dart';
import '../models/local/local_weight_log.dart';

/// The device-side database. Every read the UI performs comes from here, and
/// every write lands here first — Supabase is downstream of it, never in front.
///
/// Two rules keep the sync layer honest:
///   • mutations made *by the user* go through `save…` and enqueue an outbox
///     entry;
///   • rows pulled *from the server* go through `put…Local` and enqueue
///     nothing. Mixing the two is what turns a pull into an echo loop where
///     every download immediately re-uploads itself.
class LocalDBService {
  const LocalDBService._();

  static const _uuid = Uuid();

  // Nullable rather than `late`. If [init] fails — a corrupt box, a storage
  // permission problem, a timeout at startup — a `late` field throws
  // LateInitializationError on first touch, and since these are read during
  // widget builds that means a red screen instead of a degraded one. Null
  // simply reads as "cache empty", which every caller already handles.
  static Box<LocalDailyLog>? _dailyLogs;
  static Box<LocalMeal>? _meals;
  static Box<LocalProfile>? _profiles;
  static Box<LocalWeightLog>? _weightLogs;
  static Box<LocalSleepSchedule>? _sleepSchedules;
  static Box<LocalBlockedApp>? _blockedApps;
  static Box<LocalPendingSync>? _pendingSync;
  static Box<LocalMealRoutine>? _routines;

  static bool _ready = false;

  /// True once the boxes are open. Callers that might run before startup
  /// finishes (background isolates, early providers) check this instead of
  /// touching a `late` field that would throw.
  static bool get isReady => _ready;

  /// Bump when a change makes previously-written boxes unreadable.
  ///
  /// v2 exists because v1 registered every adapter against `dynamic` (see
  /// [_register]), so anything it wrote may deserialise as the wrong model.
  /// These boxes are a cache of Supabase, never the only copy, so dropping
  /// them is safe — the next pull refills them.
  static const _schemaVersion = 2;
  static const _keySchemaVersion = 'hive_schema_version';

  static const _boxNames = [
    'daily_logs',
    'meals',
    'profiles',
    'weight_logs',
    'sleep_schedules',
    'blocked_apps',
    'pending_sync',
    'meal_routines',
  ];

  static Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    await _migrate();

    _register(0, LocalDailyLogAdapter());
    _register(1, LocalMealAdapter());
    _register(2, LocalProfileAdapter());
    _register(3, LocalWeightLogAdapter());
    _register(4, LocalPendingSyncAdapter());
    _register(5, LocalSleepScheduleAdapter());
    _register(6, LocalBlockedAppAdapter());
    _register(7, LocalMealRoutineAdapter());

    _dailyLogs = await _openBox<LocalDailyLog>('daily_logs');
    _meals = await _openBox<LocalMeal>('meals');
    _profiles = await _openBox<LocalProfile>('profiles');
    _weightLogs = await _openBox<LocalWeightLog>('weight_logs');
    _sleepSchedules = await _openBox<LocalSleepSchedule>('sleep_schedules');
    _blockedApps = await _openBox<LocalBlockedApp>('blocked_apps');
    _pendingSync = await _openBox<LocalPendingSync>('pending_sync');
    _routines = await _openBox<LocalMealRoutine>('meal_routines');

    _ready = true;
  }

  /// Drops boxes written by an older, incompatible schema.
  static Future<void> _migrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_keySchemaVersion) ?? 1;
      if (stored >= _schemaVersion) return;
      for (final name in _boxNames) {
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await prefs.setInt(_keySchemaVersion, _schemaVersion);
      await CrashLog.record(
          'Hive cache reset: schema v$stored → v$_schemaVersion', null);
    } catch (e, s) {
      await CrashLog.record('Hive migration check failed: $e', s);
    }
  }

  /// Registers one adapter against its own model type.
  ///
  /// The `<T>` matters. Taking a bare `TypeAdapter` here made Dart infer
  /// `registerAdapter<dynamic>`, so Hive filed all seven adapters under
  /// `dynamic` and then dispatched *every* write through whichever one it
  /// matched first — reads came back as the wrong model and the profile load
  /// blew up. Hive warns about exactly this at registration time.
  static void _register<T>(int typeId, TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(typeId)) Hive.registerAdapter<T>(adapter);
  }

  /// Opens a box, rebuilding it if the file is corrupt.
  ///
  /// A half-written box (battery pull mid-write) otherwise throws on open and
  /// takes the whole app down at launch — the exact failure this feature exists
  /// to prevent. Losing the cache is recoverable; not starting is not.
  static Future<Box<T>> _openBox<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e, s) {
      await CrashLog.record('Hive box "$name" corrupt, recreating: $e', s);
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox<T>(name);
    }
  }

  static String newId() => _uuid.v4();

  // ── Daily logs ─────────────────────────────────────────────────────────────

  /// Columns each writer of a daily log actually owns.
  ///
  /// A day's row is written by four unrelated sources — food, water, the
  /// pedometer, the sleep sampler — and none of them knows anything about
  /// the other three's fields.
  static const dailyLogScopes = <String, List<String>>{
    'macros': [
      'calories_consumed',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g',
    ],
    'water': ['water_ml'],
    'steps': ['steps', 'calories_burned'],
    'sleep': [
      'sleep_hrs',
      'sleep_quality',
      'sleep_interruptions',
      'phone_pickups',
      'sleep_score',
      'sleep_start',
      'sleep_end',
    ],
    'weight': ['weight_kg'],
  };

  /// User-made change: persist and queue for upload.
  ///
  /// [scope] names which group of columns this write is responsible for, and
  /// only those are sent. This is load-bearing, not tidiness: a Supabase
  /// upsert sets exactly the columns in its payload, so pushing the whole row
  /// meant every writer overwrote all three of the others with whatever its
  /// local copy happened to hold.
  ///
  /// That is how a signed-out-then-in account lost a day's water and macros.
  /// Sign-out clears the local boxes; the dashboard then mounts and the step
  /// tracker calls [dailyLogOrEmpty], which — finding nothing cached yet,
  /// because the restoring pull is still in flight — hands back a brand new
  /// all-zero row, fills in the step count, and upserts *the entire thing*.
  /// Water and macros the server still held were zeroed by a writer that had
  /// no business touching them, and the pull that followed then dutifully
  /// restored those zeroes over the top of the local copy.
  ///
  /// Scoping the payload makes each source unable to express an opinion about
  /// fields it does not own, so a fresh empty row can no longer erase anything.
  static Future<void> saveDailyLog(LocalDailyLog log,
      {required String scope}) async {
    log.isSynced = false;
    log.lastUpdated = DateTime.now();
    await _dailyLogs?.put(log.hiveKey, log);

    final row = log.toRow();
    final columns = dailyLogScopes[scope];
    final data = columns == null
        ? row
        : {
            'user_id': row['user_id'],
            'date': row['date'],
            for (final c in columns) c: row[c],
          };

    await _enqueue(
      table: 'daily_logs',
      operation: 'upsert',
      data: data,
      // One entry per (user, day, scope) — repeat edits of the same day from
      // the same source collapse, but a pending water write is never dropped
      // by a step write landing on top of it.
      dedupeKey: 'daily_logs|${log.hiveKey}|$scope',
    );
  }

  /// Server-sourced row: persist without queuing anything.
  static Future<void> putDailyLogLocal(LocalDailyLog log) async {
    final key = log.hiveKey;
    // Any scope still queued protects the whole local row, since replacing it
    // wholesale would drop the unsent field group along with everything else.
    if ((_dailyLogs?.containsKey(key) ?? false) &&
        _hasQueuedForDay('daily_logs|$key')) {
      return;
    }
    log.isSynced = true;
    await _dailyLogs?.put(key, log);
  }

  /// Whether any scoped daily-log write for this day is still queued.
  static bool _hasQueuedForDay(String keyPrefix) =>
      (_pendingSync?.values ?? const <LocalPendingSync>[])
          .any((p) => p.dedupeKey?.startsWith(keyPrefix) ?? false);

  static LocalDailyLog? getDailyLog(String userId, DateTime date) =>
      _dailyLogs?.get(LocalDailyLog.keyFor(userId, date));

  static LocalDailyLog? getTodayLog(String userId) =>
      getDailyLog(userId, DateTime.now());

  /// Logs between [start] and [end], inclusive on both ends (day precision).
  static List<LocalDailyLog> getLogsForRange(
    String userId,
    DateTime start,
    DateTime end,
  ) {
    final from = LocalDailyLog.isoDate(start);
    final to = LocalDailyLog.isoDate(end);
    final out = <LocalDailyLog>[];
    for (final l in _dailyLogs?.values ?? const <LocalDailyLog>[]) {
      if (l.userId != userId) continue;
      final iso = LocalDailyLog.isoDate(l.date);
      if (iso.compareTo(from) >= 0 && iso.compareTo(to) <= 0) out.add(l);
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Returns the day's log, creating an empty one if it doesn't exist yet.
  /// Not persisted until a `save…` call — reading a day shouldn't write.
  static LocalDailyLog dailyLogOrEmpty(String userId, DateTime date) =>
      getDailyLog(userId, date) ??
      LocalDailyLog(
        id: '',
        userId: userId,
        date: date,
        lastUpdated: DateTime.now(),
      );

  // ── Meals ──────────────────────────────────────────────────────────────────

  static Future<void> saveMeal(LocalMeal meal) async {
    meal.isSynced = false;
    await _meals?.put(meal.id, meal);
    await _enqueue(
      table: 'meals',
      operation: 'upsert', // idempotent: id is client-generated
      data: meal.toRow(),
      dedupeKey: 'meals|${meal.id}',
    );
  }

  static Future<void> putMealLocal(LocalMeal meal) async {
    if (_blocksIncoming(_meals, meal.id, 'meals|${meal.id}') ||
        hasQueued('meals|${meal.id}|delete')) {
      return;
    }
    meal.isSynced = true;
    await _meals?.put(meal.id, meal);
  }

  static Future<void> deleteMeal(String mealId) async {
    await _meals?.delete(mealId);
    // Drop any queued write for this meal first: uploading a row and then
    // deleting it is pure churn, and if the insert never left the device the
    // delete would target a row the server has never seen.
    final hadPendingInsert = await _dropQueued('meals|$mealId');
    if (hadPendingInsert) return;
    await _enqueue(
      table: 'meals',
      operation: 'delete',
      data: {'id': mealId},
      dedupeKey: 'meals|$mealId|delete',
    );
  }

  static List<LocalMeal> getMealsForDate(String userId, DateTime date) {
    final iso = LocalDailyLog.isoDate(date);
    final out = <LocalMeal>[];
    for (final m in _meals?.values ?? const <LocalMeal>[]) {
      if (m.userId != userId) continue;
      if (LocalDailyLog.isoDate(m.date) != iso) continue;
      out.add(m);
    }
    out.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return out;
  }

  static List<LocalMeal> getTodayMeals(String userId) =>
      getMealsForDate(userId, DateTime.now());

  // ── Profile ────────────────────────────────────────────────────────────────

  static Future<void> saveProfile(LocalProfile profile) async {
    profile.isSynced = false;
    _keepCreatedAt(profile);
    await _profiles?.put(profile.id, profile);
    await _enqueue(
      table: 'profiles',
      operation: 'upsert',
      data: profile.toRow(),
      dedupeKey: 'profiles|${profile.id}',
    );
  }

  static Future<void> putProfileLocal(LocalProfile profile) async {
    if (_blocksIncoming(_profiles, profile.id, 'profiles|${profile.id}')) {
      return;
    }
    profile.isSynced = true;
    _keepCreatedAt(profile);
    await _profiles?.put(profile.id, profile);
  }

  /// Stops a write without a creation date from erasing the cached one.
  ///
  /// `created_at` belongs to the server and is never sent back up, so any
  /// profile the app builds itself — an onboarding edit, a goal change — has it
  /// as null. Persisting that null would wipe the anchor the free trial is
  /// measured from, and the three days would silently restart every time the
  /// user changed a goal.
  static void _keepCreatedAt(LocalProfile incoming) {
    if (incoming.createdAt != null) return;
    incoming.createdAt = _profiles?.get(incoming.id)?.createdAt;
  }

  static LocalProfile? getProfile(String userId) => _profiles?.get(userId);

  // ── Water ──────────────────────────────────────────────────────────────────

  /// Adds [mlToAdd] to the day's total and returns the new total.
  static Future<int> addWater(
    String userId,
    int mlToAdd, {
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now();
    final log = dailyLogOrEmpty(userId, day);
    log.waterMl += mlToAdd;
    await saveDailyLog(log, scope: 'water');
    return log.waterMl;
  }

  // ── Weight ─────────────────────────────────────────────────────────────────

  static Future<void> saveWeightLog(LocalWeightLog log) async {
    log.isSynced = false;
    await _weightLogs?.put(log.id, log);
    await _enqueue(
      table: 'weight_logs',
      operation: 'upsert',
      data: log.toRow(),
      dedupeKey: 'weight_logs|${log.id}',
    );
  }

  static Future<void> putWeightLogLocal(LocalWeightLog log) async {
    if (_blocksIncoming(_weightLogs, log.id, 'weight_logs|${log.id}')) return;
    log.isSynced = true;
    await _weightLogs?.put(log.id, log);
  }

  /// Newest first.
  static List<LocalWeightLog> getWeightHistory(String userId) {
    final out = (_weightLogs?.values ?? const <LocalWeightLog>[])
        .where((w) => w.userId == userId)
        .toList();
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  // ── Meal routines ────────────────────────────────────────────────────────
  //
  // Replaces what used to be pure SharedPreferences storage in
  // RoutineService: no server copy meant a saved routine didn't survive a
  // sign-out, a reinstall, or a second device. Same save/putLocal/delete
  // shape as everything else here, so it gets the same offline queue and the
  // same push-before-pull ordering for free.

  static Future<void> saveRoutine(LocalMealRoutine r) async {
    r.isSynced = false;
    await _routines?.put(r.id, r);
    await _enqueue(
      table: 'meal_routines',
      operation: 'upsert',
      data: r.toRow(),
      dedupeKey: 'meal_routines|${r.id}',
    );
  }

  static Future<void> putRoutineLocal(LocalMealRoutine r) async {
    if (_blocksIncoming(_routines, r.id, 'meal_routines|${r.id}')) return;
    r.isSynced = true;
    await _routines?.put(r.id, r);
  }

  static Future<void> deleteRoutine(String id) async {
    await _routines?.delete(id);
    // Same reasoning as deleteMeal: if the save never left the device there is
    // nothing on the server to delete, so drop the queued insert instead of
    // enqueueing a delete for a row that was never created.
    final hadPendingInsert = await _dropQueued('meal_routines|$id');
    if (hadPendingInsert) return;
    await _enqueue(
      table: 'meal_routines',
      operation: 'delete',
      data: {'id': id},
      dedupeKey: 'meal_routines|$id|delete',
    );
  }

  /// Newest first, matching the order Quick Picks has always shown them in.
  static List<LocalMealRoutine> getRoutines(String userId) {
    final out = (_routines?.values ?? const <LocalMealRoutine>[])
        .where((r) => r.userId == userId)
        .toList();
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ── Sleep schedule / blocked apps ──────────────────────────────────────────

  static Future<void> saveSleepSchedule(LocalSleepSchedule s) async {
    s.isSynced = false;
    await _sleepSchedules?.put(s.userId, s);
    await _enqueue(
      table: 'sleep_schedule',
      operation: 'upsert',
      data: s.toRow(),
      dedupeKey: 'sleep_schedule|${s.userId}',
    );
  }

  static Future<void> putSleepScheduleLocal(LocalSleepSchedule s) async {
    if (_blocksIncoming(
        _sleepSchedules, s.userId, 'sleep_schedule|${s.userId}')) {
      return;
    }
    s.isSynced = true;
    await _sleepSchedules?.put(s.userId, s);
  }

  static LocalSleepSchedule? getSleepSchedule(String userId) =>
      _sleepSchedules?.get(userId);

  static Future<void> saveBlockedApp(LocalBlockedApp app) async {
    app.isSynced = false;
    await _blockedApps?.put(app.hiveKey, app);
    await _enqueue(
      table: 'blocked_apps',
      operation: 'upsert',
      data: app.toRow(),
      dedupeKey: 'blocked_apps|${app.hiveKey}',
    );
  }

  static Future<void> putBlockedAppLocal(LocalBlockedApp app) async {
    if (_blocksIncoming(
        _blockedApps, app.hiveKey, 'blocked_apps|${app.hiveKey}')) {
      return;
    }
    app.isSynced = true;
    await _blockedApps?.put(app.hiveKey, app);
  }

  static List<LocalBlockedApp> getBlockedApps(String userId) =>
      (_blockedApps?.values ?? const <LocalBlockedApp>[])
          .where((a) => a.userId == userId)
          .toList();

  // ── Outbox ─────────────────────────────────────────────────────────────────

  static Future<void> _enqueue({
    required String table,
    required String operation,
    required Map<String, dynamic> data,
    String? dedupeKey,
  }) async {
    if (dedupeKey != null) await _dropQueued(dedupeKey);
    final entry = LocalPendingSync(
      id: newId(),
      table: table,
      operation: operation,
      dataJson: jsonEncode(data),
      createdAt: DateTime.now(),
      dedupeKey: dedupeKey,
    );
    await _pendingSync?.put(entry.id, entry);
  }

  /// Whether a write for this row is still waiting to be uploaded.
  ///
  /// This is what protects local edits from being overwritten by a pull. It
  /// deliberately asks the outbox rather than reading an `isSynced` flag on the
  /// row: the flag would have to be flipped back to true after a successful
  /// push, and any missed flip would pin that row's local copy forever,
  /// silently rejecting every future server update for it.
  static bool hasQueued(String dedupeKey) =>
      (_pendingSync?.values ?? const <LocalPendingSync>[])
          .any((p) => p.dedupeKey == dedupeKey);

  /// Whether a `put…Local` should skip writing — true only when there is a
  /// genuinely unsynced *local* row to protect, not merely a queue entry.
  ///
  /// [clearAll] wipes the display cache on sign-out but deliberately keeps
  /// the outbox, so a write that had not finished flushing before logout
  /// (a network blip mid-sync, say) leaves an orphaned queue entry with no
  /// local row behind it any more. Every `put…Local` here used to guard on
  /// [hasQueued] alone, which could not tell that apart from "an edit is
  /// still in flight" — so after signing back into the same account, the
  /// very first pull silently refused to write the row it had just fetched,
  /// because the box key it checked pointed at nothing. The local row never
  /// got restored until that stale entry happened to drain on its own, which
  /// on a flaky connection could be a long wait or never: today's totals
  /// read as wiped while individually-keyed siblings (a meal from three days
  /// ago, with no queue entry of its own) restored normally, which is why it
  /// looked like only *some* data had gone missing rather than all of it.
  static bool _blocksIncoming(Box? box, dynamic key, String dedupeKey) =>
      (box?.containsKey(key) ?? false) && hasQueued(dedupeKey);

  /// Removes queued entries carrying [dedupeKey]. Returns true if any existed.
  static Future<bool> _dropQueued(String dedupeKey) async {
    final doomed = (_pendingSync?.values ?? const <LocalPendingSync>[])
        .where((p) => p.dedupeKey == dedupeKey)
        .map((p) => p.id)
        .toList();
    if (doomed.isEmpty) return false;
    await _pendingSync?.deleteAll(doomed);
    return true;
  }

  /// Queue in creation order, parked entries excluded.
  static List<LocalPendingSync> getPendingSync() {
    final out = (_pendingSync?.values ?? const <LocalPendingSync>[])
        .where((p) => !p.isParked)
        .toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Everything still queued, including parked entries — for diagnostics.
  static int get pendingCount => _pendingSync?.length ?? 0;

  /// Writes that will not move without help.
  ///
  /// What the dashboard badge shows, and deliberately narrower than
  /// [pendingCount]. A queued write on a flaky connection resolves itself the
  /// moment there is signal, and so does one parked by that same outage — see
  /// [releaseNetworkParked]. Badging either of those trains the user to ignore
  /// the badge, because it appears constantly and clears on its own.
  ///
  /// What is left is a row that genuinely cannot be pushed: bad data, a schema
  /// mismatch, a rejected policy. That is worth interrupting someone for, and
  /// Diagnostics can say what it was.
  static int get stuckCount =>
      getParkedSync().where((p) => !p.parkedByNetwork).length;

  static List<LocalPendingSync> getParkedSync() =>
      (_pendingSync?.values ?? const <LocalPendingSync>[])
          .where((p) => p.isParked)
          .toList();

  static Future<void> markSynced(String id) async => _pendingSync?.delete(id);

  /// Notes why a queued write failed, so the drain loop can back off and
  /// Diagnostics can say what happened.
  ///
  /// Never throws. `entry.save()` did: a `HiveObject` remembers the box it came
  /// from and raises "This object is currently not in a box" once that row has
  /// been deleted — which happens whenever a concurrent drain pushed the same
  /// entry successfully between this one reading it and failing on it. The
  /// error handler then threw *inside* the failure path, so a single rejected
  /// row surfaced as an uncaught zone error and took the rest of the queue
  /// drain down with it. Writing by key, only when the key is still there, is
  /// idempotent and cannot resurrect a row that has already synced.
  static Future<void> recordSyncFailure(
      LocalPendingSync entry, Object error) async {
    try {
      final box = _pendingSync;
      if (box == null || !box.containsKey(entry.id)) return;
      entry.retryCount += 1;
      entry.lastError = error.toString();
      await box.put(entry.id, entry);
    } catch (_) {
      // Recording a failure must never become one.
    }
  }

  /// Clears parked entries the user has chosen to give up on.
  static Future<void> discardParkedSync() async {
    await _pendingSync?.deleteAll(getParkedSync().map((p) => p.id).toList());
  }

  /// Releases entries that parked because of connectivity, so a reconnect can
  /// retry them.
  ///
  /// Without this a spell of bad signal parked a write permanently: the drain
  /// loop reads [getPendingSync], which skips parked entries, so coming back
  /// online flushed everything *except* the rows the outage had broken. They
  /// counted against the sync badge forever with no way back.
  ///
  /// Rows parked for any other reason are left alone — those are the ones
  /// parking is actually for.
  static Future<int> releaseNetworkParked() async {
    var released = 0;
    for (final entry in getParkedSync()) {
      if (!entry.parkedByNetwork) continue;
      entry.retryCount = 0;
      await entry.save();
      released++;
    }
    return released;
  }

  /// Un-parks everything so the normal sync loop picks it up again.
  ///
  /// Parking exists to stop a genuinely bad write being retried forever, but
  /// the usual cause is a stretch of bad connectivity — five timeouts in a row
  /// park a row that would go through first try on a good network. Without a
  /// way back the entry counts against the sync badge permanently while
  /// [getPendingSync] skips it, which reads as "stuck" with no recourse.
  ///
  /// Returns how many were released.
  static Future<int> retryParkedSync() async {
    final parked = getParkedSync();
    for (final entry in parked) {
      entry.retryCount = 0;
      entry.lastError = null;
      await entry.save();
    }
    return parked.length;
  }

  // ── Teardown ───────────────────────────────────────────────────────────────

  /// Wipes cached data on sign-out. The outbox goes too — the queued writes
  /// belong to the account that's leaving and would fail RLS under the next one.
  /// Wipes the per-account display cache — everything a signed-in user reads.
  ///
  /// Deliberately does **not** touch `_pendingSync`. That box is the outbox:
  /// each entry carries a self-contained JSON payload with its own `user_id`
  /// embedded, so it does not need the row it came from to still exist
  /// locally in order to be pushed. Clearing it here on sign-out was the whole
  /// bug — a step count or meal edit that had not yet reached the server was
  /// silently destroyed the moment the user signed out, before the next sync
  /// cycle had a chance to drain it. Leaving it in place means it drains
  /// automatically the next time *any* account is signed in and online; a
  /// mismatched `user_id` in the payload is caught by Supabase RLS and the
  /// entry parks rather than leaking into the wrong account.
  ///
  /// Callers that want everything gone, unsynced work included — should that
  /// ever be needed — must clear `_pendingSync` explicitly and separately, so
  /// that destructive step is never buried inside routine sign-out.
  static Future<void> clearAll() async {
    if (!_ready) return;
    await _dailyLogs?.clear();
    await _meals?.clear();
    await _profiles?.clear();
    await _weightLogs?.clear();
    await _sleepSchedules?.clear();
    await _blockedApps?.clear();
    await _routines?.clear();
  }
}
