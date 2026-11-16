package com.proteinix

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Estimates last night's sleep by sampling the screen state on a timer.
 *
 * Sleep is the *sum* of the dark stretches inside the window, counting only
 * runs long enough to be sleep rather than a glance at the clock. The gaps
 * between them — the minutes actually awake — are excluded, which is what
 * separates this from "time in bed".
 *
 * It deliberately does not use the single longest run. That under-reports
 * precisely the nights this feature exists to describe: a wake-up at 2am
 * splitting eight hours into 3h and 5h would be reported as five, and three
 * wake-ups would report three. The hours and the wake-up count would then
 * contradict each other on the same card.
 *
 * A disturbance is only counted once the screen goes dark *again* after being
 * woken. That single rule removes the need for any "is this the morning?"
 * heuristic: the wake that ends the night is never followed by darkness, so it
 * never converts.
 *
 * ## Why sampling rather than screen-state broadcasts
 *
 * ACTION_SCREEN_ON/OFF would be exact, but they are protected broadcasts that
 * Android will not deliver to a manifest-declared receiver — they must be
 * registered at runtime, which needs a living process, which in practice means
 * a foreground service and the permanent notification Android forces with it.
 *
 * Sampling trades precision for having nothing running at all. Each check is a
 * short alarm-driven broadcast that reads [android.os.PowerManager.isInteractive]
 * and exits; between checks the app is not running in any sense. No service, no
 * notification, no permissions — and none of the OEM battery-manager failures
 * that come from asking a background service to survive eight hours.
 *
 * The cost is resolution. Transitions are pinned to the midpoint of the
 * interval that contains them, which bounds the error at half a sample rather
 * than a full one, and wake-ups shorter than a sample interval are invisible.
 *
 * Every value lives in [PREFS_NAME] rather than in memory, because nothing here
 * is alive between samples.
 */
object SleepTracker {
    const val PREFS_NAME = "sleep_guard_prefs"

    const val KEY_DATE = "night_date"
    const val KEY_DARK_MS = "night_dark_ms"
    const val KEY_RUN_START = "night_run_start"
    const val KEY_INTERRUPTIONS = "night_interruptions"
    const val KEY_PENDING_WAKE = "night_pending_wake"
    const val KEY_LAST_COUNTED = "night_last_counted"
    const val KEY_COMPLETE = "night_complete"
    const val KEY_LAST_SAMPLE = "night_last_sample"

    /**
     * Times the screen was found on inside the window.
     *
     * Counted separately from [KEY_INTERRUPTIONS] because the two answer
     * different questions and neither contains the other. An interruption is a
     * wake the user went back to sleep from, so the pickup that ends the night
     * is never one; a pickup is simply the phone being in use, whether or not
     * sleep resumed.
     *
     * Both undercount by the same mechanism — a phone picked up and put down
     * between two samples is invisible to a sampler — which is what the
     * in-app disclaimer is about.
     */
    const val KEY_PICKUPS = "night_pickups"

    /** Debounce for [noteAppOpen]; samples cannot fire fast enough to need it. */
    private const val KEY_LAST_APP_OPEN = "night_last_app_open"

    /**
     * The previous reading's clocks, against which the next interval is judged.
     *
     * `elapsedRealtime` counts every millisecond since boot. `uptimeMillis`
     * stops while the CPU is suspended. The difference between their deltas
     * across an interval is therefore exactly how long the device spent in deep
     * sleep — and a phone only suspends with the screen off and nothing holding
     * it awake.
     *
     * That is what lets a night be measured at all when the sampler comes back
     * nearly empty, and it can never invent sleep: idle time is bounded above
     * by screen-off time, so the worst case is an undercount. One real night
     * fired 27 alarms of which 3 became samples and totalled zero; this
     * measures it regardless.
     *
     * Updated at every sample and at [finish]. See [KEY_IDLE_MS] for how the
     * per-interval answers are stitched into runs.
     */
    const val KEY_LAST_ELAPSED = "night_last_elapsed"
    const val KEY_LAST_UPTIME = "night_last_uptime"

    /**
     * Idle *runs*, in wall-clock time — the stretches the device was suspended
     * rather than merely the total.
     *
     * A single total across the night answers "how much" and nothing else.
     * Placing that sleep on the clock needs to know where the idle actually
     * was: a night measured as 2h15m ending at the last reading would report
     * 1:45–4:00 for someone who slept 1:10–2:50 and then used their phone,
     * wrong at both ends.
     *
     * Runs are clipped to the sleep window as they are folded. An unclipped run
     * followed a late wake alarm to 08:08 against an 06:45 wake time, which
     * pushed the total past the window, got it clamped back to exactly the
     * window length, and turned the difference into 79 minutes of "awake in
     * bed" on a night with no wake-ups at all.
     *
     * Each sample asks whether the interval it just closed was mostly
     * suspended, and that is the same run-tracking the screen sampler does —
     * only driven by a signal that survives on phones where
     * [android.os.PowerManager.isInteractive] sampling has nothing to sample.
     */
    const val KEY_IDLE_MS = "night_idle_ms"
    const val KEY_IDLE_RUN_START = "night_idle_run_start"
    const val KEY_IDLE_RUN_END = "night_idle_run_end"
    const val KEY_IDLE_FIRST = "night_idle_first"
    const val KEY_IDLE_LAST = "night_idle_last"

    /**
     * How much of an interval must be suspended to call it sleep.
     *
     * Not 100%: a phone wakes briefly for pushes and syncs all night, so a
     * genuinely undisturbed interval still shows a little CPU time. Not 50%
     * either, which would let a half-used interval count.
     */
    private const val IDLE_FRACTION = 0.7

    /**
     * When sleep actually started and ended, as opposed to when the window did.
     *
     * The window is what the user asked for; these are what was observed. A
     * 23:30 bedtime with the first dark run starting at 00:40 is an hour of
     * lying awake on the phone, and reporting the window as the sleep period
     * would hide exactly that.
     */
    const val KEY_SLEEP_START = "night_sleep_start"
    const val KEY_SLEEP_END = "night_sleep_end"

    /**
     * Finished nights, newest last, as JSON.
     *
     * Without this a night existed only until the next [beginNight] wiped the
     * counters — so a user who woke up, never opened the app, and went to bed
     * again lost that night permanently and nothing was ever written to
     * `daily_logs`. Dart drains this on every dashboard refresh.
     */
    const val KEY_HISTORY = "night_history"

    /** Enough to cover a week away from the app; the writes are idempotent. */
    private const val HISTORY_LIMIT = 7

    /**
     * Two resumes closer together than this are one wake-up. Backgrounding the
     * app for a permission dialog or the app switcher fires `resumed` again on
     * return, and each of those is not a separate time out of bed.
     */
    private const val APP_OPEN_DEBOUNCE_MS = 5 * 60 * 1000L

    /**
     * How many screen checks actually landed. Purely diagnostic, and the single
     * most useful number when a night comes back empty: zero means the alarm
     * chain never ran, while a healthy count means it ran and genuinely saw no
     * sleep. Nothing else distinguishes those two.
     */
    const val KEY_SAMPLES = "night_samples"

    /** How often the screen state is checked across the window. */
    const val SAMPLE_INTERVAL_MS = 15 * 60 * 1000L

    /** Two wake-ups closer together than this are one disturbance, not two. */
    private const val EPISODE_GAP_MS = 20 * 60 * 1000L

    /**
     * A single dark run shorter than this is someone glancing at the time and
     * putting the phone back down, not a stretch of sleep — so it adds nothing
     * to the total. At one sample interval it is also the shortest run that can
     * be observed at all.
     */
    private const val MIN_RUN_MS = SAMPLE_INTERVAL_MS

    /**
     * And a whole night has to clear this before it is reported at all. Keeps a
     * restless hour of screen-on/screen-off from registering as a night's sleep.
     *
     * Was 45 minutes, which is longer than plenty of real naps and — more to
     * the point — longer than any window someone sets to try the feature out
     * without waiting until bedtime. A 37-minute test run measured correctly,
     * cleared every other check, and then reported nothing at all.
     *
     * Twenty is the lowest value that still means something: [MIN_RUN_MS] only
     * counts dark stretches of fifteen minutes or more, so clearing this needs
     * a qualifying stretch plus a little, rather than a single sample's worth
     * of noise.
     */
    const val MIN_SLEEP_MS = 20 * 60 * 1000L

    /** Samples stop when the night ends, so this only means "never started". */
    private const val SAMPLE_STALE_MS = 2 * SAMPLE_INTERVAL_MS + 5 * 60 * 1000L

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** How long the window lasts, handling the midnight wrap. */
    fun windowLengthMs(sleep: String, wake: String): Long {
        return try {
            val s = sleep.split(":"); val w = wake.split(":")
            val sleepMins = s[0].toInt() * 60 + s[1].toInt()
            val wakeMins = w[0].toInt() * 60 + w[1].toInt()
            val mins = if (wakeMins > sleepMins) wakeMins - sleepMins
            else (24 * 60 - sleepMins) + wakeMins
            mins * 60_000L
        } catch (e: Exception) {
            8 * 60 * 60_000L
        }
    }

    /**
     * The absolute `[start, end]` of the night on file, from [KEY_DATE].
     *
     * Everything the night measures has to be clipped to this. The wake alarm
     * is inexact and can arrive an hour late, and a sample can arrive later
     * still — so without a hard boundary the idle run stays open past the wake
     * time and counts a phone sitting on a bedside table at breakfast as sleep.
     * A real night recorded 08:08 as its end against an 06:45 wake, inflating
     * the span to 8h34m and inventing 79 minutes of "awake in bed" out of the
     * gap between that and the clamped total.
     */
    fun windowBounds(ctx: Context): Pair<Long, Long>? {
        val id = prefs(ctx).getString(KEY_DATE, null) ?: return null
        val date = id.substringBefore('|')
        val window = id.substringAfter('|', "")
        val sleepHm = window.substringBefore('-', "")
        val wakeHm = window.substringAfter('-', "")
        if (sleepHm.isEmpty() || wakeHm.isEmpty()) return null

        return try {
            val (y, mo, d) = date.split("-").map { it.toInt() }
            val (wh, wm) = wakeHm.split(":").map { it.toInt() }
            val end = Calendar.getInstance().apply {
                set(y, mo - 1, d, wh, wm, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            (end - windowLengthMs(sleepHm, wakeHm)) to end
        } catch (e: Exception) {
            null
        }
    }

    /** When the current window closes: the next occurrence of [wakeHm]. */
    fun windowEndMs(wakeHm: String): Long {
        val parts = wakeHm.split(":")
        val h = parts.getOrNull(0)?.toIntOrNull() ?: 7
        val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val now = Calendar.getInstance()
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_MONTH, 1)
        }.timeInMillis
    }

    /** Whether now falls inside [sleep, wake), handling the midnight wrap. */
    fun isTimeInWindow(sleep: String, wake: String): Boolean {
        return try {
            val now = Calendar.getInstance()
            val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val s = sleep.split(":"); val w = wake.split(":")
            val sleepMins = s[0].toInt() * 60 + s[1].toInt()
            val wakeMins = w[0].toInt() * 60 + w[1].toInt()
            if (sleepMins > wakeMins) nowMins >= sleepMins || nowMins < wakeMins
            else nowMins in sleepMins until wakeMins
        } catch (e: Exception) { false }
    }

    /**
     * The night is credited to the day the user *wakes*, so a 22:30–06:30
     * window logs against tomorrow rather than the evening it began.
     */
    private fun nightDateFor(wakeHm: String): String {
        val parts = wakeHm.split(":")
        val wh = parts.getOrNull(0)?.toIntOrNull() ?: 7
        val wm = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val now = Calendar.getInstance()
        val wake = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, wh); set(Calendar.MINUTE, wm); set(Calendar.SECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_MONTH, 1)
        }
        return "%04d-%02d-%02d".format(
            wake.get(Calendar.YEAR), wake.get(Calendar.MONTH) + 1, wake.get(Calendar.DAY_OF_MONTH)
        )
    }

    /**
     * Opens the night, or resumes the one already in progress.
     *
     * Resuming rather than resetting is what lets a re-fired bedtime alarm, a
     * reboot, or an app update mid-window keep the hours already observed.
     *
     * A night is identified by its wake *date and window*, not the date alone.
     * The date alone is not unique: moving a 23:00–06:30 window to 18:00–22:30
     * on the same day produces the same wake date, so the new session silently
     * inherited the finished one — `night_complete` stayed true while sampling
     * was live, and the previous night's total was reported as this one's.
     */
    fun beginNight(ctx: Context, sleepHm: String, wakeHm: String, screenOn: Boolean) {
        val p = prefs(ctx)
        val id = "${nightDateFor(wakeHm)}|$sleepHm-$wakeHm"
        val now = System.currentTimeMillis()

        if (p.getString(KEY_DATE, null) == id) {
            val e = p.edit().putLong(KEY_LAST_SAMPLE, now)
            // Reopen a night that was closed early. A dropped wake alarm, or a
            // sample judged against a stale window, can call finish() while the
            // user is still asleep — and without this everything after that
            // mistake is discarded, because the night is already "done".
            if (p.getBoolean(KEY_COMPLETE, false)) e.putBoolean(KEY_COMPLETE, false)
            e.apply()
            return
        }

        // The night being replaced is about to be unreachable, so bank it
        // first. Whether its wake alarm ever fired, the chain simply stopped,
        // or the user edited the schedule mid-night and changed the id, the
        // hours already observed are the only record of it that exists.
        archive(ctx)

        p.edit()
            .putString(KEY_DATE, id)
            .putLong(KEY_DARK_MS, 0L)
            // Already dark when the window opened — the user settled before
            // bedtime, so the run starts now rather than at the next sample.
            .putLong(KEY_RUN_START, if (screenOn) 0L else now)
            .putInt(KEY_INTERRUPTIONS, 0)
            .putInt(KEY_SAMPLES, 0)
            .putInt(KEY_PICKUPS, 0)
            .putLong(KEY_LAST_APP_OPEN, 0L)
            .putLong(KEY_PENDING_WAKE, 0L)
            .putLong(KEY_LAST_COUNTED, 0L)
            .putBoolean(KEY_COMPLETE, false)
            .putLong(KEY_LAST_SAMPLE, now)
            .putLong(KEY_LAST_ELAPSED, android.os.SystemClock.elapsedRealtime())
            .putLong(KEY_LAST_UPTIME, android.os.SystemClock.uptimeMillis())
            .putLong(KEY_IDLE_MS, 0L)
            .putLong(KEY_IDLE_RUN_START, 0L)
            .putLong(KEY_IDLE_RUN_END, 0L)
            .putLong(KEY_IDLE_FIRST, 0L)
            .putLong(KEY_IDLE_LAST, 0L)
            // Already dark at bedtime means sleep has effectively started; a
            // screen still on means it has not, and the first dark sample will
            // set this instead.
            .putLong(KEY_SLEEP_START, if (screenOn) 0L else now)
            .putLong(KEY_SLEEP_END, 0L)
            .apply()
    }

    /**
     * The app was brought to the foreground inside the window.
     *
     * Worth its own entry point rather than being folded into [sample] because
     * it is the one moment this feature has exact information: the screen is on
     * *now*, not at some point in the last fifteen minutes. Feeding it through
     * [sample] with the true elapsed interval closes the dark run at a far
     * better estimate than the next scheduled check would, and it is also the
     * only way a phone picked up and put down between two samples is seen at
     * all.
     */
    fun noteAppOpen(ctx: Context) {
        val p = prefs(ctx)
        if (p.getString(KEY_DATE, null) == null) return

        val now = System.currentTimeMillis()
        if (now - p.getLong(KEY_LAST_APP_OPEN, 0L) < APP_OPEN_DEBOUNCE_MS) return
        p.edit().putLong(KEY_LAST_APP_OPEN, now).apply()

        // [sample] counts the pickup itself, so this must not also count one —
        // doing both reported every night-time app open as two.
        val last = p.getLong(KEY_LAST_SAMPLE, 0L)
        val interval =
            if (last <= 0L) SAMPLE_INTERVAL_MS else (now - last).coerceAtLeast(0L)
        sample(ctx, screenOn = true, intervalMs = interval)
    }

    /**
     * How long since the previous sample actually landed.
     *
     * Alarms are inexact by design, so the gap between two samples is whatever
     * Doze allowed and not [SAMPLE_INTERVAL_MS]. Measuring it is what keeps the
     * midpoint estimate in [sample] honest: assuming the nominal interval after
     * a sample arrived nine minutes late would place every transition that
     * night in the wrong place, always in the same direction.
     *
     * Capped at two intervals. A far larger gap means the chain broke, and
     * pricing a transition at the midpoint of a three-hour hole would invent
     * detail the sampler never had.
     */
    fun sinceLastSample(ctx: Context): Long {
        val last = prefs(ctx).getLong(KEY_LAST_SAMPLE, 0L)
        if (last <= 0L) return SAMPLE_INTERVAL_MS
        return (System.currentTimeMillis() - last)
            .coerceIn(0L, 2 * SAMPLE_INTERVAL_MS)
    }

    /**
     * One screen-state check.
     *
     * [intervalMs] is how long since the previous check. A transition is pinned
     * to the midpoint of that interval rather than to now, because the screen
     * changed at some unknown point inside it — the midpoint halves the
     * expected error compared with assuming it happened at either edge.
     */
    /**
     * Folds the interval that just closed into the idle runs.
     *
     * Must run before the caller overwrites [KEY_LAST_ELAPSED] / [KEY_LAST_UPTIME],
     * because it is the delta against those that says whether the device spent
     * this interval suspended.
     *
     * [endedAt] is the wall-clock time of the reading closing the interval;
     * [startedAt] the one that opened it. Both come from the caller so a
     * midpoint-adjusted sample and an exact `finish()` can each be honest about
     * what they observed.
     */
    private fun foldIdle(ctx: Context, startedAt: Long, endedAt: Long) {
        val p = prefs(ctx)
        val prevElapsed = p.getLong(KEY_LAST_ELAPSED, 0L)
        val prevUptime = p.getLong(KEY_LAST_UPTIME, 0L)
        if (prevElapsed <= 0L) return

        val span = android.os.SystemClock.elapsedRealtime() - prevElapsed
        val awake = android.os.SystemClock.uptimeMillis() - prevUptime
        // Negative on either side means the clocks restarted — a reboot — and
        // the interval spanning it cannot be reasoned about.
        if (span <= 0L || awake < 0L) return

        // Clipped to the window the user actually asked for. A late wake alarm
        // or a stray sample arrives well after the window closed, and without
        // this the open idle run simply follows it — turning an untouched phone
        // at breakfast into more "sleep".
        val bounds = windowBounds(ctx)
        var from = startedAt
        var to = endedAt
        if (bounds != null) {
            from = startedAt.coerceIn(bounds.first, bounds.second)
            to = endedAt.coerceIn(bounds.first, bounds.second)
        }

        val e = p.edit()
        if (to > from && (span - awake) >= span * IDLE_FRACTION) {
            // Suspended for most of the interval: extend the open run, or start
            // one at the reading that opened this interval.
            if (p.getLong(KEY_IDLE_RUN_START, 0L) == 0L) {
                e.putLong(KEY_IDLE_RUN_START, from)
                if (p.getLong(KEY_IDLE_FIRST, 0L) == 0L) {
                    e.putLong(KEY_IDLE_FIRST, from)
                }
            }
            e.putLong(KEY_IDLE_RUN_END, to)
        } else {
            closeIdleRun(p, e)
        }
        e.apply()
    }

    /** Banks the open idle run, if it lasted long enough to be sleep. */
    private fun closeIdleRun(
        p: android.content.SharedPreferences,
        e: android.content.SharedPreferences.Editor,
    ) {
        val start = p.getLong(KEY_IDLE_RUN_START, 0L)
        if (start == 0L) return
        val end = p.getLong(KEY_IDLE_RUN_END, 0L)
        val run = end - start
        if (run >= MIN_RUN_MS) {
            e.putLong(KEY_IDLE_MS, p.getLong(KEY_IDLE_MS, 0L) + run)
            e.putLong(KEY_IDLE_LAST, end)
        } else if (p.getLong(KEY_IDLE_FIRST, 0L) == start) {
            // That run was too short to count and it was the first, so it must
            // not stand as the night's start time.
            e.putLong(KEY_IDLE_FIRST, 0L)
        }
        e.putLong(KEY_IDLE_RUN_START, 0L)
        e.putLong(KEY_IDLE_RUN_END, 0L)
    }

    fun sample(ctx: Context, screenOn: Boolean, intervalMs: Long = SAMPLE_INTERVAL_MS) {
        val p = prefs(ctx)
        val now = System.currentTimeMillis()
        // Before the edit below moves the elapsed/uptime bookends.
        foldIdle(ctx, p.getLong(KEY_LAST_SAMPLE, now), now)
        val edge = now - intervalMs / 2
        val runStart = p.getLong(KEY_RUN_START, 0L)
        val e = p.edit()
            .putLong(KEY_LAST_SAMPLE, now)
            .putInt(KEY_SAMPLES, p.getInt(KEY_SAMPLES, 0) + 1)
            // Every sample moves the far bookend, so the idle measurement keeps
            // widening even on a night where almost nothing else lands.
            .putLong(KEY_LAST_ELAPSED, android.os.SystemClock.elapsedRealtime())
            .putLong(KEY_LAST_UPTIME, android.os.SystemClock.uptimeMillis())

        if (screenOn) {
            if (runStart != 0L) {
                // The phone went from dark to in-use: a pickup, counted whether
                // or not the run before it was long enough to be sleep.
                e.putInt(KEY_PICKUPS, p.getInt(KEY_PICKUPS, 0) + 1)

                val run = edge - runStart
                if (run >= MIN_RUN_MS) {
                    e.putLong(KEY_DARK_MS, p.getLong(KEY_DARK_MS, 0L) + run)
                    // Woken and reaching for the phone. Only a disturbance if
                    // they go back to sleep, which the next dark run confirms.
                    e.putLong(KEY_PENDING_WAKE, now)
                    // Provisionally the end of sleep. Overwritten by every
                    // later dark run, so what survives is the last one — which
                    // is the moment sleep actually ended.
                    e.putLong(KEY_SLEEP_END, edge)
                }
                e.putLong(KEY_RUN_START, 0L)
            }
        } else {
            if (runStart == 0L) {
                e.putLong(KEY_RUN_START, edge)
                // First darkness of the night is when sleep began.
                if (p.getLong(KEY_SLEEP_START, 0L) == 0L) {
                    e.putLong(KEY_SLEEP_START, edge)
                }

                val pending = p.getLong(KEY_PENDING_WAKE, 0L)
                if (pending > 0L) {
                    if (pending - p.getLong(KEY_LAST_COUNTED, 0L) > EPISODE_GAP_MS) {
                        e.putInt(KEY_INTERRUPTIONS, p.getInt(KEY_INTERRUPTIONS, 0) + 1)
                        e.putLong(KEY_LAST_COUNTED, pending)
                    }
                    e.putLong(KEY_PENDING_WAKE, 0L)
                }
            }
        }
        e.apply()
    }

    /**
     * Closes the night at the wake time.
     *
     * The wake alarm is exact, so the closing edge is `now` rather than a
     * midpoint — there is no uncertainty about when the window ended.
     */
    fun finish(ctx: Context) {
        val p = prefs(ctx)
        // The final interval, folded in before the bookends move below.
        foldIdle(ctx, p.getLong(KEY_LAST_SAMPLE, System.currentTimeMillis()),
            System.currentTimeMillis())

        val start = p.getLong(KEY_RUN_START, 0L)
        val e = p.edit().putBoolean(KEY_COMPLETE, true).putLong(KEY_RUN_START, 0L)
            // The closing bookend, which is what makes the idle span cover the
            // whole window even when the samples in between went missing.
            .putLong(KEY_LAST_ELAPSED, android.os.SystemClock.elapsedRealtime())
            .putLong(KEY_LAST_UPTIME, android.os.SystemClock.uptimeMillis())
        // Whatever run is still open ends here — this is the wake time.
        closeIdleRun(p, e)

        if (start != 0L) {
            // Closed at `now` only when this is the wake alarm arriving on
            // time. A dropped alarm can bring us here hours late — via the
            // out-of-window guard in the receiver — and crediting the gap
            // would invent sleep nobody observed. The last sample is the
            // furthest point darkness was actually seen.
            val closeAt = maxOf(p.getLong(KEY_LAST_SAMPLE, 0L), start)
                .coerceAtMost(System.currentTimeMillis())
            val run = closeAt - start
            if (run >= MIN_RUN_MS) {
                e.putLong(KEY_DARK_MS, p.getLong(KEY_DARK_MS, 0L) + run)
                // Slept right through to the wake time, so the night ends where
                // the last darkness was observed rather than at an earlier
                // pickup.
                e.putLong(KEY_SLEEP_END, closeAt)
            }
        }
        e.apply()

        // apply() updates the in-memory map synchronously, so the archive below
        // sees the closed run and the `complete` flag this call just wrote.
        archive(ctx)
    }

    /**
     * Banks the current night into [KEY_HISTORY].
     *
     * Idempotent: an entry for the same date is replaced rather than appended,
     * so the several paths that call this — the wake alarm, the out-of-window
     * guard, the next [beginNight] — cannot produce duplicates, and re-running
     * it after more sleep was observed simply improves the stored figure.
     */
    private fun archive(ctx: Context) {
        val p = prefs(ctx)
        val night = result(ctx)
        val date = night["date"] as? String ?: return
        if ((night["hours"] as? Double ?: 0.0) <= 0.0) return

        val kept = JSONArray()
        val previous = try {
            JSONArray(p.getString(KEY_HISTORY, "[]") ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        for (i in 0 until previous.length()) {
            val entry = previous.optJSONObject(i) ?: continue
            if (entry.optString("date") != date) kept.put(entry)
        }
        kept.put(JSONObject().apply {
            put("date", date)
            put("hours", night["hours"])
            put("interruptions", night["interruptions"])
            put("phonePickups", night["phonePickups"])
            put("sleepStart", night["sleepStart"])
            put("sleepEnd", night["sleepEnd"])
            put("status", night["status"])
        })

        // Newest last, so dropping from the front sheds the oldest.
        val trimmed = JSONArray()
        val from = maxOf(0, kept.length() - HISTORY_LIMIT)
        for (i in from until kept.length()) trimmed.put(kept.get(i))

        p.edit().putString(KEY_HISTORY, trimmed.toString()).apply()
    }

    /**
     * Every finished night still on file, oldest first.
     *
     * Dart writes each of these to `daily_logs`, which is what makes a run of
     * nights survive the app not being opened in the morning.
     */
    fun history(ctx: Context): List<Map<String, Any?>> {
        val raw = try {
            JSONArray(prefs(ctx).getString(KEY_HISTORY, "[]") ?: "[]")
        } catch (e: Exception) {
            return emptyList()
        }
        return (0 until raw.length()).mapNotNull { i ->
            val entry = raw.optJSONObject(i) ?: return@mapNotNull null
            mapOf(
                "date" to entry.optString("date").ifEmpty { null },
                "hours" to entry.optDouble("hours", 0.0),
                "interruptions" to entry.optInt("interruptions", 0),
                "phonePickups" to entry.optInt("phonePickups", 0),
                "sleepStart" to entry.optLong("sleepStart", 0L),
                "sleepEnd" to entry.optLong("sleepEnd", 0L),
                "status" to entry.optString("status", "complete")
            )
        }
    }

    /**
     * What Dart persists to `daily_logs`.
     *
     * `hours` is 0 until the night clears [MIN_SLEEP_MS]. `status` is one of:
     *
     *  - `complete`    — the night is closed and the figures are final.
     *  - `in_progress` — the window is still open. Figures only grow from here,
     *                    so they are safe to write.
     *  - `partial`     — samples stopped before the wake time. Whatever was
     *                    seen is a floor of unknown depth, not a measurement.
     */
    fun result(ctx: Context): Map<String, Any?> {
        val p = prefs(ctx)
        val now = System.currentTimeMillis()
        val sleepHm = p.getString("sleepTime", "23:00") ?: "23:00"
        val wakeHm = p.getString("wakeTime", "07:00") ?: "07:00"

        // Include the run still open, so a query at 3am reports the sleep so
        // far rather than only the stretches already closed.
        //
        // Bounded by the last sample, not by now. An open run is only evidence
        // of darkness up to the moment something last looked; measuring it to
        // the present assumes the phone stayed dark through however long the
        // alarms were missing. A night whose closing alarm never fired reported
        // 9.9 hours against a 5.5-hour window, because it was still counting at
        // breakfast.
        val start = p.getLong(KEY_RUN_START, 0L)
        val lastSample = p.getLong(KEY_LAST_SAMPLE, 0L)
        val observedTo = maxOf(lastSample, start)
        val open = if (start == 0L) 0L else (observedTo - start).coerceAtLeast(0L)

        // And no night can exceed its own window. Belt and braces against any
        // other path that leaves a run open — sleeping longer than the window
        // is simply not something this can observe.
        val windowMs = windowLengthMs(sleepHm, wakeHm)
        val sampled = (p.getLong(KEY_DARK_MS, 0L) +
            (if (open >= MIN_RUN_MS) open else 0L)).coerceAtMost(windowMs)

        // How long the device was actually suspended between the first and last
        // moment this night was touched. See KEY_IDLE_MS: the CPU only
        // suspends with the screen off, so this is a lower bound on screen-off
        // time and can never manufacture sleep.
        //
        // The larger of the two wins. Sampling is the better *description* of a
        // night — it knows where the gaps were — but it is only as good as the
        // alarms that landed, and when those go missing it reports zero for a
        // night that plainly happened. Idle has no such failure mode.
        // The banked runs, plus whichever is still open — so a night queried
        // mid-way reports the sleep so far rather than only what has closed.
        //
        // This replaced a cruder figure: total suspended time between the
        // night's first and last reading. That was unbounded, so a late wake
        // alarm made it exceed the window and it came back *clamped to the
        // window length* — which is how a 7h15m window reported exactly 7h15m
        // of sleep and looked like a measurement. The runs are clipped to the
        // window as they are folded, so this is a figure rather than a ceiling.
        val openIdleStart = p.getLong(KEY_IDLE_RUN_START, 0L)
        val openIdle = if (openIdleStart == 0L) 0L
            else (p.getLong(KEY_IDLE_RUN_END, 0L) - openIdleStart).coerceAtLeast(0L)
        val idle = (p.getLong(KEY_IDLE_MS, 0L) +
            (if (openIdle >= MIN_RUN_MS) openIdle else 0L)).coerceAtMost(windowMs)

        val total = maxOf(sampled, idle)

        val stale = now - lastSample > SAMPLE_STALE_MS
        val status = when {
            p.getBoolean(KEY_COMPLETE, false) -> "complete"
            stale -> "partial"
            else -> "in_progress"
        }

        // The night is still running, so its end is "so far" — the last point
        // darkness was actually seen, never the present.
        var sleepStart = p.getLong(KEY_SLEEP_START, 0L)
        var sleepEnd = when (val recorded = p.getLong(KEY_SLEEP_END, 0L)) {
            0L -> if (start != 0L) observedTo else 0L
            else -> maxOf(recorded, if (start != 0L) observedTo else 0L)
        }

        // When idle carried the night, the screen sampler's timestamps describe
        // a night it never actually saw — usually not at all, leaving the sleep
        // screen to fall back on the times the user *scheduled* rather than
        // anything observed. The idle runs know where the sleep really was.
        if (idle > sampled) {
            val idleFrom = p.getLong(KEY_IDLE_FIRST, 0L)
            val idleTo = maxOf(
                p.getLong(KEY_IDLE_LAST, 0L),
                if (openIdle >= MIN_RUN_MS) p.getLong(KEY_IDLE_RUN_END, 0L) else 0L,
            )
            if (idleFrom > 0L && idleTo > idleFrom) {
                sleepStart = idleFrom
                sleepEnd = idleTo
            }
        }

        // Last line of defence. Whichever source supplied them, a night cannot
        // begin before its window or end after it — and the span these two
        // describe is what "awake in bed" is derived from, so a timestamp
        // outside the window does not just look wrong, it manufactures
        // wakefulness that never happened.
        val bounds = windowBounds(ctx)
        if (bounds != null) {
            if (sleepStart > 0L) sleepStart = sleepStart.coerceIn(bounds.first, bounds.second)
            if (sleepEnd > 0L) sleepEnd = sleepEnd.coerceIn(bounds.first, bounds.second)
            if (sleepEnd <= sleepStart) sleepEnd = 0L
        }

        return mapOf(
            // Stored as "<date>|<window>" so a changed window starts a fresh
            // night; only the date half means anything to the caller.
            "date" to p.getString(KEY_DATE, null)?.substringBefore('|'),
            "hours" to if (total < MIN_SLEEP_MS) 0.0 else total / 3_600_000.0,
            // The unfloored figure, and the bar it has to clear.
            //
            // Through `hours` alone, "nothing was measured" and "something was
            // measured and then discarded for being short" are the same zero —
            // so the sleep screen told a user it had recorded nothing on a
            // night it had in fact watched for 37 minutes. Only Diagnostics
            // knew the difference. These two let every screen say which it is.
            "observedMs" to total,
            "minimumMs" to MIN_SLEEP_MS,
            "interruptions" to p.getInt(KEY_INTERRUPTIONS, 0),
            "phonePickups" to p.getInt(KEY_PICKUPS, 0),
            "sleepStart" to sleepStart,
            "sleepEnd" to sleepEnd,
            "status" to status,
            // Exposed for Diagnostics. When a night comes back empty these are
            // the values that say why: samples that stop hours before the wake
            // time mean the alarm chain broke, not that no sleep happened.
            "lastSample" to lastSample,
            "samples" to p.getInt(KEY_SAMPLES, 0),
            // Which of the two measurements won, for Diagnostics. "sampled"
            // means the alarms did their job; "idle" means they largely didn't
            // and the night was recovered from the suspend clock instead.
            "source" to if (idle > sampled) "idle" else "sampled"
        )
    }
}
