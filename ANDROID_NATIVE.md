# Android Native Files — Copy verbatim into your Flutter project

After running `flutter create .` inside `nutiai_flutter/`, replace/create the following files.

---

## `android/app/build.gradle.kts`

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nutiai"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.nutiai"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }
}

flutter { source = "../.." }

dependencies {
    implementation("androidx.health.connect:connect-client:1.1.0-alpha07")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.guava:guava:32.1.3-android")
    implementation("androidx.core:core-ktx:1.13.1")
}
```

---

## `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.health.READ_STEPS"/>
    <uses-permission android:name="android.permission.health.READ_SLEEP"/>

    <application android:label="NutiAI" android:icon="@mipmap/ic_launcher" android:name="${applicationName}">
        <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTop"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:windowSoftInputMode="adjustResize">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme"/>
            <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
        </activity>
        <service android:name=".SleepTrackingService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="sleepTracking"/>
        </service>
        <receiver android:name=".SleepTrackingReceiver" android:exported="false"/>
        <meta-data android:name="flutterEmbedding" android:value="2"/>
    </application>
</manifest>
```

---

## `MainActivity.kt`  (`android/app/src/main/kotlin/com/nutiai/`)

```kotlin
package com.nutiai
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.nutiai/sleep_tracking").setMethodCallHandler { call, res ->
            when (call.method) {
                "startTracking" -> {
                    val sleep = call.argument<String>("sleepTime") ?: "23:00"
                    val wake  = call.argument<String>("wakeTime")  ?: "07:00"
                    SleepTrackingAlarmManager.schedule(this, sleep, wake); res.success(true)
                }
                "stopTracking" -> { SleepTrackingAlarmManager.cancel(this); stopService(Intent(this, SleepTrackingService::class.java)); res.success(true) }
                // "armed" is the user's button; "running" is whether the window
                // is open now. The card needs both — armed-but-not-running is a
                // real state for most of the day, not an off state.
                "getTrackingState" -> res.success(mapOf(
                    "armed" to getSharedPreferences(SleepTrackingService.PREFS_NAME, MODE_PRIVATE).getBoolean("active", false),
                    "running" to SleepTrackingService.isRunning
                ))
                "getSleepResult" -> res.success(SleepTracker.result(this))
                else -> res.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.nutiai/health_connect").setMethodCallHandler { call, res ->
            when (call.method) {
                "checkHealthConnectAvailable" -> res.success(HealthConnectManager.isAvailable(this))
                "requestHealthPermissions" -> scope.launch { res.success(HealthConnectManager.requestPermissions(this@MainActivity)) }
                "getStepsToday" -> scope.launch { res.success(HealthConnectManager.stepsToday(this@MainActivity)) }
                "getSleepToday" -> scope.launch { res.success(HealthConnectManager.sleepHoursToday(this@MainActivity)) }
                else -> res.notImplemented()
            }
        }
    }
}
```

---

## Sleep tracking

Four files, none reproduced here — the source is short and the comments in it
carry the reasoning:

| File | Job |
|---|---|
| `SleepTracker.kt` | The algorithm and all state, in `SharedPreferences`. Nothing is held in memory, because nothing is alive between samples. |
| `SleepTrackingAlarmManager.kt` | The alarms: bedtime, wake, and a self-chaining sample. |
| `SleepTrackingReceiver.kt` | Turns those alarms into work. The entire runtime of the feature. |
| `SleepReportNotifier.kt` | The morning report, posted natively because no Flutter engine is alive at the wake time. |

**The whole feature declares one permission: `RECEIVE_BOOT_COMPLETED`.** No
foreground service, no wake locks, no exact-alarm permissions, no
`PACKAGE_USAGE_STATS`, no `AccessibilityService`. Keep it that way — see the
note in `AndroidManifest.xml` for what each of those was and why it went.

There is **no foreground service** and therefore no permanent notification.
`ACTION_SCREEN_ON`/`OFF` are protected broadcasts that Android will not deliver
to a manifest-declared receiver — they need a runtime registration, which needs
a living process, which in practice means a foreground service. Sampling the
screen state from short alarm broadcasts avoids all of that.

Alarms are set with `setAndAllowWhileIdle` and never the `setExact*` variants.
`AllowWhileIdle` is load-bearing — the window is spent in Doze, and a plain
`set` would defer everything to the next maintenance window. The inexact half is
a product decision: exact alarms need SCHEDULE_EXACT_ALARM, which is denied by
default on Android 14+ and so costs the user a trip to Settings before anything
works. Enabling notifications is meant to be the entire setup.

That decision has a measured cost. On an Infinix running XOS, inexact alarms
were dropped outright — a whole night returned `night_samples = 0`. Two things
compensate, and both matter:

- **Sample alarms are pre-scheduled, not chained.** Each slot is independent, so
  a dropped alarm costs one sample instead of the rest of the night. This is the
  single most important property of the design; do not "simplify" it back into a
  self-perpetuating chain.
- **`SleepTracker.sinceLastSample` measures the real gap** rather than assuming
  15 minutes, so `sample` prices each transition at the midpoint of the interval
  that actually elapsed.

Opening the app re-books every remaining slot, which is the cheapest recovery
available when the OEM has eaten a run of them.

Load-bearing, and easy to undo by accident:

- **Every alarm must re-arm the next one.** AlarmManager one-shots do not
  repeat. The bedtime alarm re-arms itself for tomorrow, the wake alarm rebuilds
  both ends, and each sample schedules the next. Removing any of those makes
  tracking work for exactly one night and then stop, with the card still
  reporting ARMED because the preference it reads is not the thing that lapsed.
- **Rescheduling both alarms is only safe outside the window.** At 2am inside a
  23:30–05:00 window, "the next bedtime" is tonight and "the next wake after
  it" is tomorrow — which cancels this morning's stop alarm.
- **A finished night must be archived before the next one opens.** `beginNight`
  resets the counters; without `KEY_HISTORY` a user who woke up and didn't open
  the app before the following bedtime lost that night outright.
- **A wake-up is only counted once the screen goes dark again.** A disturbance
  is something you returned to sleep from, so the morning pickup never
  converts — no "is this the alarm?" heuristic needed.
- **`interruptions` and `phonePickups` are not interchangeable.** A pickup is
  the screen found on; an interruption is a pickup that sleep resumed after.
  Only `interruptions` is written to `sleep_interruptions`, because pickups
  include the one that ends the night and an undisturbed night would otherwise
  report as one wake-up.

### The resolution limit

A phone picked up at 3:04 and put down at 3:09 falls between two samples and is
invisible. This is inherent to sampling, not a bug to fix, and both the wake-up
count and `phone_pickups` are floors because of it. The sleep screen says so in
as many words — do not remove that disclaimer.

`UsageStatsManager.queryEvents()` would close the gap exactly, and a previous
revision of this feature used it. It was removed on purpose: it needs
`PACKAGE_USAGE_STATS`, which is sensitive-data special access requiring a Data
Safety declaration and prominent disclosure, for a feature that already works
without it. Do not reintroduce it without a reason that survives Play review.

## `HealthConnectManager.kt`

```kotlin
package com.nutiai
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.LocalDate
import java.time.ZoneId

object HealthConnectManager {
    private val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class)
    )

    fun isAvailable(ctx: Context) = HealthConnectClient.getSdkStatus(ctx) == HealthConnectClient.SDK_AVAILABLE

    suspend fun requestPermissions(activity: ComponentActivity): Boolean {
        if (!isAvailable(activity)) return false
        val client = HealthConnectClient.getOrCreate(activity)
        val granted = client.permissionController.getGrantedPermissions()
        return granted.containsAll(permissions)
    }

    suspend fun stepsToday(ctx: Context): Int {
        if (!isAvailable(ctx)) return 0
        val client = HealthConnectClient.getOrCreate(ctx)
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now().atStartOfDay(zone).toInstant()
        val end = java.time.Instant.now()
        val req = ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(start, end))
        return client.readRecords(req).records.sumOf { it.count.toInt() }
    }

    suspend fun sleepHoursToday(ctx: Context): Double {
        if (!isAvailable(ctx)) return 0.0
        val client = HealthConnectClient.getOrCreate(ctx)
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now().minusDays(1).atTime(18,0).atZone(zone).toInstant()
        val end = java.time.Instant.now()
        val req = ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(start, end))
        val total = client.readRecords(req).records.sumOf { java.time.Duration.between(it.startTime, it.endTime).toMinutes() }
        return total / 60.0
    }
}
```

---

---


## Final setup checklist

1. `flutter create .` (from inside `nutiai_flutter/` — only creates missing platform folders)
2. Replace the files above
3. `cp .env.example .env` and fill in keys
4. Paste `supabase_schema.sql` into Supabase SQL Editor → Run
5. `flutter pub get && flutter run`

Done.
