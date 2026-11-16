import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_service.dart';

/// Tracks whether the device has a network path, and kicks the outbox whenever
/// one appears.
///
/// "Has a network path" is not "can reach Supabase" — connectivity_plus only
/// reports the radio/interface state, so a captive-portal wifi or a dead cell
/// tower still reads as online. Every network call therefore keeps its own
/// timeout; this class decides *when to try*, never whether a call will work.
class ConnectivityService {
  const ConnectivityService._();

  static final _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static bool _isOnline = false;
  static bool get isOnline => _isOnline;

  static final _controller = StreamController<bool>.broadcast();

  /// Emits on every change to [isOnline]. Widgets watch this instead of the
  /// raw connectivity stream so they see the same view of the world the sync
  /// layer does.
  static Stream<bool> get onStatusChange => _controller.stream;

  static Future<void> initialize() async {
    _isOnline = _readable(await _safeCheck());

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _setOnline(_readable(results));

      // Came back online — flush anything queued while we were away.
      if (wasOffline && _isOnline) {
        unawaited(SyncService.syncPendingData());
      }
    });
  }

  static Future<bool> checkConnection() async {
    _setOnline(_readable(await _safeCheck()));
    return _isOnline;
  }

  static Future<List<ConnectivityResult>> _safeCheck() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (_) {
      // Platform channel unavailable — assume online rather than locking the
      // user out of the AI features on a false negative.
      return const [ConnectivityResult.wifi];
    }
  }

  /// connectivity_plus 6 reports a *list* of active interfaces; a device is
  /// offline only when every entry says none.
  static bool _readable(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  static void _setOnline(bool value) {
    if (_isOnline == value) return;
    _isOnline = value;
    _controller.add(value);
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
