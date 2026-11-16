import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

/// Small badge shown when a write cannot reach Supabase without help.
///
/// Deliberately silent about the ordinary queue. Logging a meal on a weak
/// connection queues it, retries it, and gets it through minutes later without
/// the user doing anything — badging that is noise, and a badge that appears
/// constantly and clears by itself is one people stop reading.
///
/// So this counts only writes that are genuinely stuck: parked for a reason
/// that is not connectivity, because those never resolve on their own. See
/// [LocalDBService.stuckCount].
class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({super.key});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  StreamSubscription<void>? _sub;
  int _stuck = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = SyncService.onSyncChanged.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!LocalDBService.isReady) return;
    final count = LocalDBService.stuckCount;
    if (mounted && count != _stuck) setState(() => _stuck = count);
  }

  @override
  Widget build(BuildContext context) {
    if (_stuck == 0) return const SizedBox.shrink();

    // A warning rather than a spinner: nothing is in progress, and showing one
    // would suggest waiting is enough. It isn't — Diagnostics has the reason
    // and the retry.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 13, color: AppColors.error),
          const SizedBox(width: 6),
          Text('$_stuck not synced',
              style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
