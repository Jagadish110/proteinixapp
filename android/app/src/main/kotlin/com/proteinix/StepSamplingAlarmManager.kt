package com.proteinix

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * Keeps a step-counter reading landing every half hour, forever.
 *
 * Unlike sleep, this has no window and no end — the counter has to be anchored
 * across every midnight, so sampling simply never stops.
 *
 * ## Why several alarms rather than one
 *
 * A chain — each sample booking the next — dies permanently the first time an
 * OEM battery manager eats a delivery, and this one has no bedtime alarm to
 * restart it the following night. [SLOTS] alarms are therefore booked ahead at
 * staggered offsets and all of them re-booked on every fire, so losing one
 * costs a single reading rather than the feature. That is the same lesson
 * [SleepTrackingAlarmManager] learned from an Infinix that returned
 * `night_samples = 0`.
 *
 * Missing samples degrade gracefully in any case: a stale anchor only means
 * the day falls back to counting from the first app open, which is exactly
 * where this started.
 */
object StepSamplingAlarmManager {
    const val ACTION_SAMPLE = "com.proteinix.SAMPLE_STEPS"

    private const val REQ_BASE = 300

    /** Two hours of cover at the 30-minute interval. */
    private const val SLOTS = 4

    private fun pending(ctx: Context, slot: Int) =
        PendingIntent.getBroadcast(
            ctx,
            REQ_BASE + slot,
            Intent(ctx, StepSamplingReceiver::class.java).setAction(ACTION_SAMPLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * `setAndAllowWhileIdle`, never the exact variants — see the manifest for
     * why exact alarms are deliberately not requested. Doze will widen these,
     * which costs precision at the midnight anchor and nothing else.
     */
    fun schedule(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val step = StepCounter.SAMPLE_INTERVAL_MIN * 60_000L
        val now = System.currentTimeMillis()
        for (slot in 0 until SLOTS) {
            try {
                am.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    now + step * (slot + 1),
                    pending(ctx, slot),
                )
            } catch (e: Exception) {
                // One slot refused is survivable; the others still cover.
            }
        }
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        for (slot in 0 until SLOTS) am.cancel(pending(ctx, slot))
    }
}
