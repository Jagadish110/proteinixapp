package com.proteinix

import android.app.*
import android.content.*
import java.util.Calendar

/**
 * Drives the whole feature from AlarmManager alone — there is no service.
 *
 * One alarm at bedtime to open the night, one at the wake time to close it, and
 * a *pre-scheduled* sample alarm for every slot in between.
 *
 * ## Why the samples are pre-scheduled and not chained
 *
 * They used to chain: each sample scheduled the next one when it fired. That
 * keeps the pending-alarm list short, and it is fatal on a phone that drops
 * alarms — because a single missed delivery ends the night. There is no sample
 * left to schedule a successor, so nothing runs again until morning.
 *
 * That is not hypothetical. An Infinix running XOS came back with
 * `night_samples = 0` against a six-hour window: the night opened correctly,
 * the first sample was dropped, and the chain simply stopped existing.
 *
 * Scheduling every slot up front makes each one independent. The OEM can eat
 * two thirds of them and the remaining third still measures the night — badly,
 * but measurably, which is the difference between a number and a blank. It also
 * costs nothing: a 24-slot night is well inside Android 14's 500-alarm cap.
 */
object SleepTrackingAlarmManager {
    private const val REQ_START = 101
    private const val REQ_STOP = 102

    /** Sample slots occupy [REQ_SAMPLE_BASE, REQ_SAMPLE_BASE + MAX_SAMPLES). */
    private const val REQ_SAMPLE_BASE = 200

    /**
     * Slots per night. 100 covers a 25-hour window at the 15-minute interval,
     * so the cap can only bite on a nonsensical schedule.
     */
    private const val MAX_SAMPLES = 100

    const val ACTION_START = "com.proteinix.START_TRACKING"
    const val ACTION_STOP = "com.proteinix.STOP_TRACKING"
    const val ACTION_SAMPLE = "com.proteinix.SAMPLE_SLEEP"

    private fun pending(ctx: Context, req: Int, action: String, wake: String?) =
        PendingIntent.getBroadcast(
            ctx, req,
            Intent(ctx, SleepTrackingReceiver::class.java)
                .setAction(action)
                .apply { if (wake != null) putExtra("wakeTime", wake) },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    /**
     * `setAndAllowWhileIdle`, always — never the `setExact*` variants.
     *
     * `AllowWhileIdle` is the load-bearing half: the entire window is spent in
     * Doze, and a plain `set` would be deferred to the next maintenance window.
     *
     * The inexact half is a product decision, not a technical one. Exact alarms
     * need SCHEDULE_EXACT_ALARM, which is denied by default on Android 14+ and
     * so costs the user a trip to Settings before the feature works at all;
     * enabling notifications is meant to be the whole setup. The cost is real —
     * these alarms carry a delivery *window*, and an OEM power manager may
     * widen it or drop them outright — which is exactly why the samples are
     * independent rather than chained, and why [SleepTracker.sinceLastSample]
     * measures the interval that actually elapsed instead of assuming 15
     * minutes.
     */
    private fun set(ctx: Context, atMs: Long, pi: PendingIntent) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
    }

    /** The next occurrence of `HH:mm` strictly after now. */
    private fun nextOccurrence(hm: String, fallbackHour: Int): Long {
        val parts = hm.split(":")
        val h = parts.getOrNull(0)?.toIntOrNull() ?: fallbackHour
        val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val now = Calendar.getInstance()
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_MONTH, 1)
        }.timeInMillis
    }

    fun schedule(ctx: Context, sleepHm: String, wakeHm: String) {
        // Slots left over from a previous window would fire inside the new one
        // and sample a night that isn't running. Rescheduling always starts
        // from a clean set.
        cancelSamples(ctx)

        val now = System.currentTimeMillis()
        val startAt = nextOccurrence(sleepHm, 22)
        // The next wake from *now*, not from the next bedtime. Arming at 2am
        // inside a 23:30–05:00 window has to stop at 05:00 this morning.
        val stopAt = nextOccurrence(wakeHm, 6)

        set(ctx, startAt, pending(ctx, REQ_START, ACTION_START, wakeHm))
        set(ctx, stopAt, pending(ctx, REQ_STOP, ACTION_STOP, null))

        // Switching on mid-window has to start sampling now; the bedtime alarm
        // for this night has already passed and will not fire again until
        // tomorrow.
        if (SleepTracker.isTimeInWindow(sleepHm, wakeHm)) {
            scheduleSamples(ctx, now, stopAt, wakeHm)
        }
    }

    /**
     * Pushes the bedtime alarm to tomorrow, leaving tonight's wake alarm and
     * samples alone.
     *
     * Called the moment the bedtime alarm fires. AlarmManager one-shots do not
     * repeat and nothing else re-arms this one, so without it tracking works
     * for exactly one night and then stays silent — with the card still
     * reporting ARMED, because the preference it reads was never what lapsed.
     *
     * Parses defensively: unlike [nextOccurrence], this has no fallback of its
     * own further up the call chain, and it runs first inside the ACTION_START
     * receiver specifically so a failure elsewhere in that handler still
     * leaves tomorrow armed. A bad or missing time string here must not throw
     * — it must fall back to a sane default and keep tracking alive instead.
     */
    fun rearmStart(ctx: Context, sleepHm: String, wakeHm: String) {
        val (sh, sm) = try {
            sleepHm.split(":").map { it.toInt() }
        } catch (e: Exception) {
            listOf(23, 0)
        }
        val at = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, sh); set(Calendar.MINUTE, sm)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_MONTH, 1)
        }
        set(ctx, at.timeInMillis, pending(ctx, REQ_START, ACTION_START, wakeHm))
    }

    /**
     * Books every remaining sample between [fromMs] and [untilMs].
     *
     * Idempotent: the slots are re-derived from the clock each time and reuse
     * the same request codes, so calling this again — on app open, at bedtime,
     * after a reboot — replaces the set rather than doubling it. That is what
     * lets opening the app mid-night restore whatever the OEM has already
     * eaten.
     */
    fun scheduleSamples(ctx: Context, fromMs: Long, untilMs: Long, wakeHm: String) {
        var at = fromMs + SleepTracker.SAMPLE_INTERVAL_MS
        var slot = 0
        while (at < untilMs && slot < MAX_SAMPLES) {
            set(ctx, at, pending(ctx, REQ_SAMPLE_BASE + slot, ACTION_SAMPLE, wakeHm))
            at += SleepTracker.SAMPLE_INTERVAL_MS
            slot++
        }
        // Anything beyond the new tail is a leftover from a longer window.
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (stale in slot until MAX_SAMPLES) {
            am.cancel(pending(ctx, REQ_SAMPLE_BASE + stale, ACTION_SAMPLE, null))
        }
    }

    fun cancelSamples(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (slot in 0 until MAX_SAMPLES) {
            am.cancel(pending(ctx, REQ_SAMPLE_BASE + slot, ACTION_SAMPLE, null))
        }
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx, REQ_START, ACTION_START, null))
        am.cancel(pending(ctx, REQ_STOP, ACTION_STOP, null))
        cancelSamples(ctx)
    }
}
