import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';

/// Raw connectivity transitions. Prefer [isOnlineProvider] in widgets.
final connectivityStreamProvider =
    StreamProvider<bool>((ref) => ConnectivityService.onStatusChange);

/// Whether the device currently has a network path.
///
/// Falls back to the service's cached value so the very first build is already
/// correct — a screen gated on this must not flash its online state for a frame
/// while waiting for the stream's first event (the stream only emits on
/// *change*, so with a stable connection it may never emit at all).
final isOnlineProvider = Provider<bool>((ref) =>
    ref.watch(connectivityStreamProvider).value ??
    ConnectivityService.isOnline);
