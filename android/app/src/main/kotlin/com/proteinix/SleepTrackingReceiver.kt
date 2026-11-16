package com.proteinix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * The whole runtime of sleep tracking.
 *
 * Each delivery does a few milliseconds of work and returns; nothing stays
 * resident between them. That is the entire reason this feature no longer runs
 * a foreground service or shows a permanent notification.
 */
class SleepTrackingReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val prefs = ctx.getSharedPreferences(
            SleepTracker.PREFS_NAME, Context.MODE_PRIVATE)

        // Preferences first, the Intent extra only as a fallback.
        //
        // It was the other way round, and the extra is a *snapshot* taken when
        // the alarm was booked. Edit the schedule and every alarm already in
        // flight still carries the old wake time, so samples get judged against
        // a window that no longer exists. Last night that sent 24 of 27 sample
        // broadcasts down the out-of-window branch — which closed the night
        // instead of measuring it, and left the total at zero.
        val wake = prefs.getString("wakeTime", null)
            ?: intent.getStringExtra("wakeTime") ?: "07:00"

        when (intent.action) {
            SleepTrackingAlarmManager.ACTION_START -> {
                if (!prefs.getBoolean("active", false)) return
                val sleep = prefs.getString("sleepTime", "23:00") ?: "23:00"

                // Tonight's alarm has now been spent. Book tomorrow's first,
                // before anything below that could throw, so a crash further
                // down still leaves tracking armed for the next night.
                SleepTrackingAlarmManager.rearmStart(ctx, sleep, wake)

                SleepTracker.beginNight(ctx, sleep, wake, screenOn(ctx))
                // Book every sample for tonight at once. Chained samples died
                // with the first dropped alarm; independent ones survive
                // whatever the OEM decides to eat.
                SleepTrackingAlarmManager.scheduleSamples(
                    ctx,
                    System.currentTimeMillis(),
                    SleepTracker.windowEndMs(wake),
                    wake,
                )
            }

            SleepTrackingAlarmManager.ACTION_SAMPLE -> {
                if (!prefs.getBoolean("active", false)) return
                val sleep = prefs.getString("sleepTime", "23:00") ?: "23:00"
                // The stop alarm closes the night; if it was dropped, a sample
                // arriving late is the fallback that notices — and has to
                // rebuild the schedule too, since the alarm that would have
                // done it never came.
                if (!SleepTracker.isTimeInWindow(sleep, wake)) {
                    SleepTracker.finish(ctx)
                    SleepTrackingAlarmManager.schedule(ctx, sleep, wake)
                    return
                }
                // Open the night if nothing else has. The bedtime alarm is the
                // usual opener, but it is one inexact alarm with an hour-wide
                // delivery window — and if it is dropped, every sample that
                // follows accumulates into whatever stale night was left in
                // preferences instead of tonight's. Idempotent when the night
                // is already open.
                val open = SleepTracker.sinceLastSample(ctx)
                SleepTracker.beginNight(ctx, sleep, wake, screenOn(ctx))
                // Measured, not assumed: these alarms are inexact and slots can
                // go missing, so the real gap is whatever actually elapsed.
                SleepTracker.sample(ctx, screenOn(ctx), open)
            }

            SleepTrackingAlarmManager.ACTION_STOP -> {
                SleepTrackingAlarmManager.cancelSamples(ctx)
                SleepTracker.finish(ctx)

                // Read after finish(), so the figures include the run the wake
                // alarm just closed — which is usually the bulk of the night.
                val night = SleepTracker.result(ctx)
                SleepReportNotifier.show(
                    ctx,
                    (night["hours"] as? Double) ?: 0.0,
                    (night["interruptions"] as? Int) ?: 0
                )

                if (!prefs.getBoolean("active", false)) return
                // Rebuild both ends for the next night. Safe here and nowhere
                // else in the window: at the wake time the next bedtime and the
                // next wake are, in that order, tonight and tomorrow morning.
                val sleep = prefs.getString("sleepTime", "23:00") ?: "23:00"
                SleepTrackingAlarmManager.schedule(ctx, sleep, wake)
            }
        }
    }

    private fun screenOn(ctx: Context): Boolean =
        (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
}
