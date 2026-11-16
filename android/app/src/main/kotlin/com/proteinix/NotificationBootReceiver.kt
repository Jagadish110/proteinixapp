package com.proteinix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Flags that the reminder alarms need re-registering.
 *
 * Android drops every pending AlarmManager alarm on reboot and on app update.
 * flutter_local_notifications ships its own boot receiver that replays them
 * from disk, but on OEM skins that restore is unreliable (and it can't recover
 * at all if the plugin's own store was cleared by a "phone cleaner"). This is
 * the belt to that braces: the flag is picked up by
 * `NotificationService.restoreIfNeeded()` the next time the app is opened, and
 * the whole schedule is rewritten from the user's saved settings.
 *
 * The flag is written into Flutter's own SharedPreferences file with the
 * `flutter.` key prefix that the shared_preferences plugin uses, so the Dart
 * side can read it with a plain `prefs.getBool(...)` — no method channel and no
 * engine start-up needed here.
 */
class NotificationBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> Unit
            else -> return
        }

        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_NEEDS_RESCHEDULE, true)
            .apply()
    }

    private companion object {
        /** File name used by the shared_preferences Flutter plugin. */
        const val FLUTTER_PREFS = "FlutterSharedPreferences"

        /** Must stay in sync with NotificationService.keyNeedsReschedule. */
        const val KEY_NEEDS_RESCHEDULE = "flutter.notif_needs_reschedule"
    }
}
