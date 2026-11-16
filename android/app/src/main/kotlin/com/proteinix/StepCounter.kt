package com.proteinix

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import java.util.Calendar

/**
 * Counts today's steps whether or not the app has been opened.
 *
 * ## The problem this exists for
 *
 * `TYPE_STEP_COUNTER` keeps counting while the app is closed — it is a
 * hardware register — but it reports one cumulative total since boot and
 * carries no history. A total on its own cannot be split across a midnight,
 * so the Dart pedometer anchored each new day at *the first reading it saw
 * that day*, which is whenever the app happened to be opened. Everything
 * walked before that was discarded.
 *
 * For anyone who walks before opening the app — which is most mornings — that
 * is the whole morning gone. It reads as "steps only count when I press the
 * button", because the first open of the day is what started the count.
 *
 * The missing piece was never the arithmetic. It was a reading taken *near
 * midnight*, when no one is running the app. So take one: a short alarm-driven
 * broadcast every [SAMPLE_INTERVAL_MIN] minutes reads the counter and banks
 * `(value, timestamp)`. The reading that lands just before midnight becomes
 * the next day's anchor, and the morning is measured from there.
 *
 * Same shape as [SleepTracker] and for the same reasons: no foreground
 * service, no permanent notification, no permissions beyond the
 * ACTIVITY_RECOGNITION grant the sensor already needs. Each delivery does a
 * few milliseconds of work and exits.
 */
object StepCounter {
    const val PREFS_NAME = "step_counter_prefs"

    /** The day [KEY_DAY_START_RAW] is an anchor for, as `yyyy-MM-dd`. */
    private const val KEY_DAY = "step_day"

    /** Counter value as of the start of [KEY_DAY]. */
    private const val KEY_DAY_START_RAW = "step_day_start_raw"

    /** The most recent reading, and when it was taken. */
    private const val KEY_LAST_RAW = "step_last_raw"
    private const val KEY_LAST_AT = "step_last_at"

    /**
     * Steps banked before a same-day reboot.
     *
     * The counter restarts at zero when the device does, so the day's total is
     * whatever was counted before the restart plus whatever has accrued since.
     * Without this a reboot at lunchtime wiped the morning.
     */
    private const val KEY_CARRY = "step_carry"

    const val KEY_TODAY = "step_today"

    /** Purely diagnostic: how many samples have landed today. */
    const val KEY_SAMPLES = "step_samples"

    /** How often the counter is read. */
    const val SAMPLE_INTERVAL_MIN = 30

    /**
     * How stale the previous reading may be and still anchor a new day.
     *
     * The anchor is the last reading before midnight, so steps taken between
     * that reading and midnight are credited to the wrong day. At a
     * 30-minute interval that error is bounded by half an hour of walking at
     * midnight, which is close enough to zero to ignore.
     *
     * It stops being close to zero once sampling has been down for hours — an
     * OEM cleaner killed the chain, the phone was off. Crediting a whole
     * evening's walking to the following morning is the failure the Dart side
     * hit when it tried this without a bound: a phone put down after an
     * evening walk opened on ~1,100 steps against 54 actually taken.
     *
     * Beyond this, fall back to anchoring at the current reading — the old
     * behaviour, losing the gap rather than inventing it. Missing steps are a
     * floor; invented ones are a lie.
     */
    private const val ANCHOR_GRACE_MS = 90 * 60 * 1000L

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun dayOf(ms: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        return "%04d-%02d-%02d".format(
            c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH)
        )
    }

    private fun midnightOf(ms: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    /**
     * Folds one raw counter reading into today's total.
     *
     * Idempotent for a repeated value: the same [raw] twice yields the same
     * total, so a sample arriving alongside an app-open costs nothing.
     */
    fun record(ctx: Context, raw: Long, now: Long) {
        val p = prefs(ctx)
        val today = dayOf(now)
        val lastRaw = p.getLong(KEY_LAST_RAW, -1L)
        val lastAt = p.getLong(KEY_LAST_AT, 0L)

        var dayStart = p.getLong(KEY_DAY_START_RAW, -1L)
        var carry = p.getInt(KEY_CARRY, 0)

        if (p.getString(KEY_DAY, null) != today) {
            // New day. Anchor on the last reading before midnight when it is
            // recent enough to mean anything, otherwise on the reading in hand.
            dayStart = if (lastRaw in 0..raw && lastAt >= midnightOf(now) - ANCHOR_GRACE_MS) {
                lastRaw
            } else {
                raw
            }
            carry = 0
            p.edit()
                .putString(KEY_DAY, today)
                .putInt(KEY_SAMPLES, 0)
                .apply()
        } else if (raw < lastRaw || dayStart < 0) {
            // The counter went backwards inside a single day, which only
            // happens when the device restarted. Bank the total so far and
            // start again from the fresh zero.
            carry = p.getInt(KEY_TODAY, 0)
            dayStart = 0L
        }

        val today0 = (carry + (raw - dayStart)).coerceIn(0L, 200_000L).toInt()

        p.edit()
            .putLong(KEY_DAY_START_RAW, dayStart)
            .putInt(KEY_CARRY, carry)
            .putLong(KEY_LAST_RAW, raw)
            .putLong(KEY_LAST_AT, now)
            .putInt(KEY_TODAY, today0)
            .putInt(KEY_SAMPLES, p.getInt(KEY_SAMPLES, 0) + 1)
            .apply()
    }

    /**
     * Today's total, or 0 once the stored figure belongs to a previous day.
     *
     * Checked against the wall clock rather than trusted: crossing midnight
     * with no sample yet would otherwise keep reporting yesterday.
     */
    fun todaySteps(ctx: Context): Int {
        val p = prefs(ctx)
        return if (p.getString(KEY_DAY, null) == dayOf(System.currentTimeMillis())) {
            p.getInt(KEY_TODAY, 0)
        } else {
            0
        }
    }

    /** What Diagnostics reads. */
    fun state(ctx: Context): Map<String, Any?> {
        val p = prefs(ctx)
        return mapOf(
            "steps" to todaySteps(ctx),
            "samples" to p.getInt(KEY_SAMPLES, 0),
            "lastAt" to p.getLong(KEY_LAST_AT, 0L),
            "day" to p.getString(KEY_DAY, null),
        )
    }

    /**
     * Reads the counter once and hands back the value, or null.
     *
     * `TYPE_STEP_COUNTER` is an on-change sensor, so registering delivers the
     * current value straight away rather than waiting for the next step. The
     * timeout covers the cases where it does not: no such sensor, or the
     * ACTIVITY_RECOGNITION grant missing, both of which register without
     * error and then simply never call back.
     */
    fun read(ctx: Context, timeoutMs: Long = 5_000, done: (Long?) -> Unit) {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sm == null || sensor == null) {
            done(null)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var settled = false

        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                if (settled) return
                settled = true
                sm.unregisterListener(this)
                handler.removeCallbacksAndMessages(null)
                done(e.values.firstOrNull()?.toLong())
            }

            override fun onAccuracyChanged(s: Sensor?, accuracy: Int) {}
        }

        val ok = try {
            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        } catch (e: Exception) {
            false
        }
        if (!ok) {
            done(null)
            return
        }

        handler.postDelayed({
            if (settled) return@postDelayed
            settled = true
            try {
                sm.unregisterListener(listener)
            } catch (e: Exception) {
                // Already gone; nothing to undo.
            }
            done(null)
        }, timeoutMs)
    }

    /** Read and fold in one call. [done] reports today's total afterwards. */
    fun sample(ctx: Context, done: (Int) -> Unit) {
        read(ctx) { raw ->
            if (raw != null) record(ctx, raw, System.currentTimeMillis())
            done(todaySteps(ctx))
        }
    }
}
