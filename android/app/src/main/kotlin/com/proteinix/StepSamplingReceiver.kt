package com.proteinix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * One step-counter reading, then gone.
 *
 * Reading a sensor is asynchronous — the value arrives on a callback — and a
 * BroadcastReceiver is dead the moment `onReceive` returns. [goAsync] holds
 * the process alive for the few hundred milliseconds the sensor needs;
 * [StepCounter.read] caps its own wait well inside the ~10s a receiver is
 * allowed, so the pending result is always finished.
 */
class StepSamplingReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != StepSamplingAlarmManager.ACTION_SAMPLE) return

        // Re-book first, before anything below can throw. A failure reading
        // the sensor must not be what ends the sampling.
        StepSamplingAlarmManager.schedule(ctx)

        val pending = goAsync()
        try {
            StepCounter.sample(ctx) { pending.finish() }
        } catch (e: Exception) {
            pending.finish()
        }
    }
}
