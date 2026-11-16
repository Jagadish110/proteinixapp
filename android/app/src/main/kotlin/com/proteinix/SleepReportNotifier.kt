package com.proteinix

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The morning report, posted the moment the wake alarm closes the night.
 *
 * Built natively rather than through `flutter_local_notifications` because
 * there is no Flutter engine here to reach it — the wake alarm arrives in a
 * BroadcastReceiver, and starting an engine to post one notification would undo
 * the whole point of a feature that keeps nothing resident.
 *
 * The channel is created here too, for the same reason: on a phone that has
 * been rebooted and not opened since, `NotificationService` has never run and
 * the channel would not exist. Creating one that already exists is a no-op, so
 * doing it on every post is both safe and the only way to be sure.
 */
object SleepReportNotifier {

    /** Distinct from the `sleep_reminders_v4` channel, which is bedtime nudges. */
    private const val CHANNEL_ID = "sleep_report_v1"
    private const val NOTIFICATION_ID = 8801

    /** Read by [MainActivity] to route the tap once Dart is alive. */
    const val EXTRA_ROUTE = "com.proteinix.ROUTE"

    fun show(ctx: Context, hours: Double, interruptions: Int) {
        // Nothing measured, nothing worth waking someone up to read.
        if (hours <= 0.0) return

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Sleep Report",
                    // Default, not high: this arrives at the wake time, and a
                    // heads-up banner with a sound would be a second alarm the
                    // user never asked for.
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Your sleep summary each morning"
                }
            )
        }

        val total = (hours * 60).toInt()
        val duration = "${total / 60}h ${total % 60}m"
        val body = when (interruptions) {
            0 -> "You slept $duration, undisturbed."
            1 -> "You slept $duration, waking once."
            else -> "You slept $duration, waking $interruptions times."
        }

        val tap = PendingIntent.getActivity(
            ctx,
            NOTIFICATION_ID,
            Intent(ctx, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .putExtra(EXTRA_ROUTE, "/sleep")
                // Reuses the existing task rather than stacking a second copy
                // of the app on top of it.
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(ctx, CHANNEL_ID)
            // The same silhouette every other reminder uses, so the report
            // reads as part of the app rather than as a system message.
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Good morning! 🌅")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()

        try {
            nm.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS refused on Android 13+. The report is still on
            // the sleep screen; there is nothing to recover here.
        }
    }
}
