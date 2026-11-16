package com.proteinix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores the sleep tracking and step sampling alarms after anything that
 * wipes them.
 *
 * A reboot is the obvious case — AlarmManager drops every alarm when the device
 * restarts. MY_PACKAGE_REPLACED is the one that actually bit: Android cancels an
 * app's alarms when the app is updated, so every install left tracking "armed"
 * in preferences with nothing scheduled to fire. The card said ARMED, the user
 * went to sleep, and no service ever started. Nothing surfaced the difference.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") return

        // Step sampling first, and unconditionally: it has no on/off switch —
        // the counter has to stay anchored across every midnight whether or
        // not sleep tracking is on. A reboot drops these alarms like any
        // other, and nothing else re-books them.
        StepSamplingAlarmManager.schedule(ctx)

        val prefs = ctx.getSharedPreferences(
            SleepTracker.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return

        // Rescheduling also restarts the sample chain when this lands
        // mid-window, and the counters survive in preferences — so a reboot
        // or an update costs at most one sample interval, not the night.
        SleepTrackingAlarmManager.schedule(
            ctx,
            prefs.getString("sleepTime", "23:00") ?: "23:00",
            prefs.getString("wakeTime", "07:00") ?: "07:00",
        )
    }
}
