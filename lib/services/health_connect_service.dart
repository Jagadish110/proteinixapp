import 'package:flutter/services.dart';

/// Calls into native Kotlin Health Connect bridge.
class HealthConnectService {
  static const _ch = MethodChannel('com.proteinix/health_connect');

  Future<bool> available() async =>
      (await _ch.invokeMethod<bool>('checkHealthConnectAvailable')) ?? false;

  /// Whether the Health Connect read permissions are already granted.
  /// Shows no UI — safe to call on every refresh.
  Future<bool> hasPermissions() async {
    try {
      return (await _ch.invokeMethod<bool>('hasHealthPermissions')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Launches Health Connect's permission screen.
  ///
  /// Only ever call this from an explicit user action. It starts an Activity,
  /// which pauses the app — and anything that re-runs on resume will loop.
  Future<bool> requestPermissions() async =>
      (await _ch.invokeMethod<bool>('requestHealthPermissions')) ?? false;

  /// Today's step count, or 0 when permission hasn't been granted.
  ///
  /// This used to call [requestPermissions] on every invocation. Home's
  /// tracking refresh runs on every `resumed` lifecycle event, so the
  /// permission Activity paused the app, and dismissing it resumed the app and
  /// requested again — an endless dialog loop that stole window focus roughly
  /// twice a second. Nothing else could hold focus while it ran, which is why
  /// the keyboard never appeared anywhere in the app.
  Future<int> stepsToday() async {
    try {
      if (!await hasPermissions()) return 0;
      return (await _ch.invokeMethod<int>('getStepsToday')) ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<double> sleepHoursToday() async =>
      (await _ch.invokeMethod<double>('getSleepToday')) ?? 0;

  /// Active energy (kcal) burned today from Health Connect.
  /// Returns 0.0 when Health Connect is unavailable or the native
  /// 'getCaloriesToday' handler has not yet been added to HealthConnectBridge.kt.
  Future<double> caloriesToday() async {
    try {
      return (await _ch.invokeMethod<double>('getCaloriesToday')) ?? 0.0;
    } on MissingPluginException {
      return 0.0;
    } on PlatformException {
      return 0.0;
    }
  }
}
