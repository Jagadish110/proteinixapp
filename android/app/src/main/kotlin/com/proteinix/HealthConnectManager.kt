package com.proteinix
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
import java.time.Instant

object HealthConnectManager {
    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class)
    )

    fun isAvailable(ctx: Context) = HealthConnectClient.getSdkStatus(ctx) == HealthConnectClient.SDK_AVAILABLE

    /// Reports whether the read permissions are already granted, *without*
    /// showing anything to the user.
    ///
    /// The Dart side previously had no way to ask this, so every step read went
    /// through [requestPermissions] — which launches an Activity. Combined with
    /// a resume-triggered refresh that produced an endless dialog loop.
    suspend fun hasPermissions(ctx: Context): Boolean {
        return try {
            if (!isAvailable(ctx)) return false
            val client = HealthConnectClient.getOrCreate(ctx)
            client.permissionController.getGrantedPermissions().containsAll(permissions)
        } catch (e: Exception) {
            false
        }
    }

    suspend fun requestPermissions(activity: ComponentActivity): Boolean {
        if (!isAvailable(activity)) return false
        val client = HealthConnectClient.getOrCreate(activity)
        val granted = client.permissionController.getGrantedPermissions()
        if (granted.containsAll(permissions)) {
            return true
        }
        if (activity is MainActivity) {
            return activity.launchHealthPermissions(permissions).await()
        }
        return false
    }

    suspend fun stepsToday(ctx: Context): Int {
        return try {
            if (!isAvailable(ctx)) return 0
            val client = HealthConnectClient.getOrCreate(ctx)
            val zone = ZoneId.systemDefault()
            val start = LocalDate.now().atStartOfDay(zone).toInstant()
            val end = Instant.now()
            if (start >= end) return 0
            val req = ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(start, end))
            client.readRecords(req).records.sumOf { it.count.toInt() }
        } catch (e: Exception) {
            0
        }
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
