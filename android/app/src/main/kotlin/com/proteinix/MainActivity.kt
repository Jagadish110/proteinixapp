package com.proteinix
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import androidx.health.connect.client.PermissionController

class MainActivity : FlutterFragmentActivity() {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /**
     * Where a tapped notification wants Dart to go.
     *
     * The morning sleep report is posted from a BroadcastReceiver with no
     * Flutter engine alive, so it cannot use the `flutter_local_notifications`
     * payload route the other reminders take. It carries the destination as an
     * Intent extra instead, and Dart drains it once it is running.
     *
     * `singleTop` means a tap while the app is already open arrives at
     * [onNewIntent] rather than a fresh [onCreate], so both have to be read.
     */
    private var pendingRoute: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(SleepReportNotifier.EXTRA_ROUTE)?.let {
            pendingRoute = it
        }
    }

    companion object {
        var healthConnectPermissionResult: CompletableDeferred<Boolean>? = null
    }

    private val healthConnectPermissionLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        healthConnectPermissionResult?.complete(granted.containsAll(HealthConnectManager.permissions))
    }

    fun launchHealthPermissions(permissions: Set<String>): CompletableDeferred<Boolean> {
        val deferred = CompletableDeferred<Boolean>()
        healthConnectPermissionResult = deferred
        runOnUiThread {
            healthConnectPermissionLauncher.launch(permissions)
        }
        return deferred
    }



    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.proteinix/sleep_tracking").setMethodCallHandler { call, res ->
            try {
                when (call.method) {
                    "startTracking" -> {
                        val sleep = call.argument<String>("sleepTime") ?: "23:00"
                        val wake = call.argument<String>("wakeTime") ?: "07:00"
                        getSharedPreferences(SleepTracker.PREFS_NAME, MODE_PRIVATE).edit()
                            .putBoolean("active", true)
                            .putString("sleepTime", sleep)
                            .putString("wakeTime", wake)
                            .apply()
                        // Opens the night immediately when switched on inside
                        // the window; otherwise the bedtime alarm does it.
                        if (SleepTracker.isTimeInWindow(sleep, wake)) {
                            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                            SleepTracker.beginNight(this, sleep, wake, pm.isInteractive)
                        }
                        SleepTrackingAlarmManager.schedule(this, sleep, wake)
                        res.success(true)
                    }
                    "stopTracking" -> {
                        getSharedPreferences(SleepTracker.PREFS_NAME, MODE_PRIVATE).edit()
                            .putBoolean("active", false).apply()
                        SleepTrackingAlarmManager.cancel(this)
                        // Switching off mid-window used to leave the night
                        // open: no alarm was left to close it, and every
                        // self-heal path is gated on `active`, so it stayed
                        // "in_progress" indefinitely and kept being reported as
                        // last night. Closing it here banks what was actually
                        // observed and ends it there.
                        SleepTracker.finish(this)
                        res.success(true)
                    }

                    // "armed" is the user's button; "running" is whether the
                    // window is open right now. Reporting only the latter made
                    // the dashboard control snap back to OFF whenever it was
                    // switched on outside the sleep window — tracking was
                    // scheduled correctly, but nothing said so.
                    "getTrackingState" -> {
                        val prefs = getSharedPreferences(
                            SleepTracker.PREFS_NAME, MODE_PRIVATE)
                        val armed = prefs.getBoolean("active", false)
                        val sleep = prefs.getString("sleepTime", "23:00") ?: "23:00"
                        val wake = prefs.getString("wakeTime", "07:00") ?: "07:00"
                        val inWindow = SleepTracker.isTimeInWindow(sleep, wake)

                        // Opening the app re-books every remaining slot. The
                        // alarms are inexact by design, so an OEM battery
                        // manager can quietly drop a run of them; rebooking is
                        // idempotent and the cheapest recovery there is — a
                        // 3am glance at the phone repairs the rest of the
                        // night.
                        if (armed && inWindow) {
                            // And opens the night if the bedtime alarm hasn't.
                            // That alarm carries an hour-wide delivery window
                            // now that it is inexact, and can be dropped
                            // outright — in which case nothing would ever call
                            // beginNight and the night simply would not exist.
                            // Idempotent: a night already open for this window
                            // keeps its counters, so this can only add one.
                            val pm = getSystemService(POWER_SERVICE)
                                as android.os.PowerManager
                            SleepTracker.beginNight(this, sleep, wake, pm.isInteractive)
                            SleepTrackingAlarmManager.scheduleSamples(
                                this,
                                System.currentTimeMillis(),
                                SleepTracker.windowEndMs(wake),
                                wake,
                            )
                        }

                        // And outside it, rebuild both ends of the window. An
                        // OEM battery manager that drops the bedtime alarm
                        // disarms the feature permanently and silently; this
                        // brings it back the next time the app is opened. Only
                        // safe out of window — mid-window it would move
                        // tonight's stop alarm a day out.
                        if (armed && !inWindow) {
                            SleepTrackingAlarmManager.schedule(this, sleep, wake)
                            // Closes last night if the wake alarm never landed.
                            // finish() is idempotent — a night already closed by
                            // that alarm just gets re-archived with the same
                            // figures — so this costs nothing on the common path
                            // and is the only thing that saves the uncommon one:
                            // without it, a dropped wake alarm left the night
                            // "in_progress" (or eventually "partial") until the
                            // *next* bedtime alarm happened to sweep it up, which
                            // is what "sleep updates late" actually was.
                            SleepTracker.finish(this)
                        }

                        res.success(mapOf(
                            "armed" to armed,
                            // No service to ask any more — being inside the
                            // window *is* what running means now.
                            "running" to (armed && inWindow)
                        ))
                    }
                    "getSleepResult" -> {
                        // Same self-heal as getTrackingState, on the path the
                        // dashboard actually reads through: a night whose wake
                        // alarm got dropped by the OS stayed "in_progress" (or
                        // eventually "partial") indefinitely, because nothing
                        // that runs on a plain dashboard open ever closed it.
                        val p = getSharedPreferences(SleepTracker.PREFS_NAME, MODE_PRIVATE)
                        val sleep = p.getString("sleepTime", "23:00") ?: "23:00"
                        val wake = p.getString("wakeTime", "07:00") ?: "07:00"
                        if (p.getBoolean("active", false) &&
                            !SleepTracker.isTimeInWindow(sleep, wake)) {
                            SleepTracker.finish(this)
                        }
                        res.success(SleepTracker.result(this))
                    }

                    // Drained, not just read: a route consumed twice would
                    // yank the user back to the sleep screen on every resume
                    // for the rest of the session.
                    "consumeLaunchRoute" -> {
                        val route = pendingRoute
                            ?: intent?.getStringExtra(SleepReportNotifier.EXTRA_ROUTE)
                        pendingRoute = null
                        intent?.removeExtra(SleepReportNotifier.EXTRA_ROUTE)
                        res.success(route)
                    }

                    /// Every finished night still on file. Dart writes these to
                    /// `daily_logs`, which is what lets a night survive the app
                    /// not being opened before the following bedtime.
                    "getSleepHistory" -> res.success(SleepTracker.history(this))

                    // The app came to the foreground. Inside an open window that
                    // is a phone pickup the 15-minute samples would otherwise
                    // miss entirely, and the one moment the screen state is
                    // known exactly rather than to the nearest sample.
                    "noteAppOpen" -> {
                        val prefs = getSharedPreferences(
                            SleepTracker.PREFS_NAME, MODE_PRIVATE)
                        val sleep = prefs.getString("sleepTime", "23:00") ?: "23:00"
                        val wake = prefs.getString("wakeTime", "07:00") ?: "07:00"
                        if (prefs.getBoolean("active", false) &&
                            SleepTracker.isTimeInWindow(sleep, wake)) {
                            SleepTracker.noteAppOpen(this)
                        }
                        res.success(true)
                    }
                    else -> res.notImplemented()
                }
            } catch (e: Exception) {
                res.error("SLEEP_TRACKING_ERROR", e.message, null)
            }
        }
        // Steps counted by the native sampler, which keeps running when the
        // app does not. See StepCounter for why the Dart pedometer alone could
        // never count a morning walk taken before the app was opened.
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.proteinix/step_tracking")
            .setMethodCallHandler { call, res ->
                try {
                    when (call.method) {
                        // Take a reading now and re-book the alarms, then
                        // report the day's total. Called on every app open:
                        // the alarms are inexact and an OEM cleaner can drop a
                        // run of them, and rebooking is the cheapest recovery
                        // there is.
                        "syncSteps" -> {
                            StepSamplingAlarmManager.schedule(this)
                            StepCounter.sample(this) { steps -> res.success(steps) }
                        }
                        "getSteps" -> res.success(StepCounter.todaySteps(this))
                        "getStepState" -> res.success(StepCounter.state(this))
                        else -> res.notImplemented()
                    }
                } catch (e: Exception) {
                    res.error("STEP_TRACKING_ERROR", e.message, null)
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.proteinix/health_connect").setMethodCallHandler { call, res ->
            when (call.method) {
                "checkHealthConnectAvailable" -> {
                    try {
                        res.success(HealthConnectManager.isAvailable(this))
                    } catch (e: Exception) {
                        res.success(false)
                    }
                }
                // Read-only check: never shows UI. Callers that just want data
                // must use this, not requestHealthPermissions.
                "hasHealthPermissions" -> scope.launch {
                    try {
                        res.success(HealthConnectManager.hasPermissions(this@MainActivity))
                    } catch (e: Exception) {
                        res.success(false)
                    }
                }
                "requestHealthPermissions" -> scope.launch {
                    try {
                        res.success(HealthConnectManager.requestPermissions(this@MainActivity))
                    } catch (e: Exception) {
                        res.success(false)
                    }
                }
                "getStepsToday" -> scope.launch {
                    try {
                        res.success(HealthConnectManager.stepsToday(this@MainActivity))
                    } catch (e: Exception) {
                        res.success(0)
                    }
                }
                "getSleepToday" -> scope.launch {
                    try {
                        res.success(HealthConnectManager.sleepHoursToday(this@MainActivity))
                    } catch (e: Exception) {
                        res.success(0.0)
                    }
                }
                else -> res.notImplemented()
            }
        }
    }
}
