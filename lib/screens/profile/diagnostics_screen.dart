import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/crash_log.dart';
import '../../models/local/local_pending_sync.dart';
import '../../services/local_db_service.dart';
import '../../services/sleep_tracking_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/ui/ui.dart';

/// Shows anything the app caught and swallowed. If the app closes unexpectedly,
/// reopen it and check here — the entry survives the restart.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<String> _entries = const [];
  List<LocalPendingSync> _parked = const [];
  SleepTrackingStatus _sleep = SleepTrackingStatus.defaults;
  SleepNight _night = SleepNight.none;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await CrashLog.read();
    final sleep = await SleepTrackingService.status();
    final night = await SleepTrackingService.lastNight();
    if (mounted) {
      setState(() {
        _entries = entries;
        _parked = LocalDBService.getParkedSync();
        _sleep = sleep;
        _night = night;
        _loading = false;
      });
    }
  }

  /// Releases parked writes back to the sync loop.
  ///
  /// The usual reason a write parks is a run of bad connectivity, not bad
  /// data, so retrying is the right default — and until this existed there was
  /// no way back at all: the entry counted against the sync badge forever
  /// while the retry loop deliberately skipped it.
  Future<void> _retryParked() async {
    setState(() => _busy = true);
    final released = await LocalDBService.retryParkedSync();
    await SyncService.syncPendingData();
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Retrying $released queued write'
              '${released == 1 ? '' : 's'}…')),
    );
  }

  Future<void> _discardParked() async {
    final count = _parked.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text('Discard $count write${count == 1 ? '' : 's'}?',
            style: AppText.headlineMd()),
        content: Text(
          'This data was saved on this device but never reached the server. '
          'Discarding it cannot be undone.',
          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep',
                style: AppText.bodyBold(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Discard',
                style: AppText.bodyBold(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDBService.discardParkedSync();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: TerraAppBar(
        title: 'Diagnostics',
        actions: [
          if (_entries.isNotEmpty)
            CircleIconButton(
              icon: Icons.delete_outline_rounded,
              onTap: () async {
                await CrashLog.clear();
                await _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                  AppSpacing.page, AppSpacing.lg),
              children: [
                _sleepCard(),
                const SizedBox(height: AppSpacing.gutter),
                if (_parked.isNotEmpty) ...[
                  _parkedCard(),
                  const SizedBox(height: AppSpacing.gutter),
                ],
                if (_entries.isEmpty)
                  const TerraCard(
                    child: Row(
                      children: [
                        Icon(Icons.verified_outlined,
                            color: AppColors.secondary, size: 20),
                        SizedBox(width: 10),
                        Expanded(child: Text('No errors recorded')),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < _entries.length; i++) ...[
                    TerraCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      onTap: () => _copy(_entries[i]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionLabel('Entry ${i + 1}',
                              color: AppColors.error,
                              trailing: Text('TAP TO COPY',
                                  style: AppText.labelCaps(size: 9))),
                          const SizedBox(height: 8),
                          SelectableText(
                            _entries[i],
                            style: AppText.bodySm(color: AppColors.onSurface)
                                .copyWith(fontFamily: 'monospace', height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
    );
  }

  /// Writes that never reached the server.
  ///
  /// Parking after five failures stops a genuinely bad row being retried
  /// forever, and keeping it on disk is right — silently discarding a logged
  /// meal would be worse. But the sync badge counts parked entries while the
  /// retry loop skips them, so without this the count sits there permanently
  /// with nothing to explain or clear it.
  Widget _parkedCard() {
    return TerraCard(
      borderColor: AppColors.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Not synced', color: AppColors.error),
          const SizedBox(height: 8),
          Text(
            '${_parked.length} write${_parked.length == 1 ? '' : 's'} saved on '
            'this device but not on the server. Your data is safe here — this '
            'is usually a run of bad connectivity, so retrying normally works.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in _parked) ...[
            const Divider(color: AppColors.outline, height: 18),
            Text('${entry.operation} ${entry.table}',
                style: AppText.labelCaps(color: AppColors.onSurface, size: 11)),
            const SizedBox(height: 3),
            Text(
              '${entry.retryCount} attempts · ${_iso(entry.createdAt)}',
              style: AppText.labelCaps(size: 10),
            ),
            if (entry.lastError case final err?) ...[
              const SizedBox(height: 4),
              Text(err,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant)
                      .copyWith(fontFamily: 'monospace', height: 1.35)),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Retry now',
                  icon: Icons.refresh_rounded,
                  height: 44,
                  glow: false,
                  loading: _busy,
                  onPressed: _busy ? null : _retryParked,
                ),
              ),
              const SizedBox(width: 10),
              MiniPill(
                label: 'Discard',
                background: AppColors.surfaceContainerHigh,
                foreground: AppColors.error,
                border: AppColors.error,
                onTap: _busy ? null : _discardParked,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  /// Why last night did or didn't record.
  ///
  /// Sleep tracking is otherwise a black box: the dashboard card shows OFF and
  /// nothing distinguishes "you never switched it on" from "the alarms stopped
  /// firing at 3am". Every value here had to be read over USB to answer that
  /// question once, which is not a debugging story anyone can repeat.
  Widget _sleepCard() {
    final n = _night;
    final beat = n.lastSample;
    final age = beat == null ? null : DateTime.now().difference(beat);

    final outcome = switch ((n.date == null, n.status, n.hours > 0)) {
      (true, _, _) => 'Nothing recorded yet',
      (_, _, false) => 'Recorded, but too little to count as a night',
      // Saved, not dropped: a truncated night is a floor, and setSleep only
      // ever raises what is stored. The warning still stands, because the
      // figure understates the night by an unknown amount.
      (_, SleepNightStatus.partial, _) =>
        'Saved — but checks stopped before the wake time',
      (_, SleepNightStatus.inProgress, _) => 'In progress',
      _ => 'Saved',
    };

    return TerraCard(
      onTap: () => _copy(_report(outcome, age)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Sleep tracking',
              color: AppColors.tertiary,
              trailing: Text('TAP TO COPY', style: AppText.labelCaps(size: 9))),
          const SizedBox(height: 10),
          _row('State', _sleep.phase.label),
          _row('Window', '${_sleep.bedtime} – ${_sleep.wake}'),
          _row(
            'Last screen check',
            age == null ? 'never' : '${_ago(age)} ago',
            // Samples stop when the night closes, so a stale value is only
            // meaningful mid-window — but a gap far larger than the window
            // means the alarm chain broke rather than the night being quiet.
            warn: age != null && age > const Duration(hours: 12),
          ),
          _row('Screen checks', '${n.samples}',
              // Zero checks on a night that reported nothing is the alarm
              // chain never running — a different fault from a quiet night.
              warn: n.date != null && n.samples == 0),
          const Divider(color: AppColors.outline, height: 20),
          _row('Night of', n.date == null ? '—' : _iso(n.date!)),
          _row('Hours', n.hours <= 0 ? '—' : n.summary ?? '—'),
          _row('Wake-ups', n.date == null ? '—' : '${n.interruptions}'),
          _row('Phone pickups', n.date == null ? '—' : '${n.phonePickups}'),
          _row('Slept', _span(n.sleepStart, n.sleepEnd)),
          _row('Outcome', outcome, warn: n.status == SleepNightStatus.partial),
        ],
      ),
    );
  }

  String _report(String outcome, Duration? age) => [
        'State: ${_sleep.phase.label}',
        'Window: ${_sleep.bedtime} - ${_sleep.wake}',
        'Last screen check: ${age == null ? 'never' : '${_ago(age)} ago'}',
        'Screen checks: ${_night.samples}',
        'Night of: ${_night.date == null ? '-' : _iso(_night.date!)}',
        'Hours: ${_night.hours.toStringAsFixed(2)}',
        'Wake-ups: ${_night.interruptions}',
        'Phone pickups: ${_night.phonePickups}',
        'Slept: ${_span(_night.sleepStart, _night.sleepEnd)}',
        'Status: ${_night.status.name}',
        'Outcome: $outcome',
      ].join('\n');

  /// The observed sleep period, which is not the window the user set — a wide
  /// gap between the two is time spent awake in bed, and the fastest way to
  /// tell that apart from a tracking fault.
  static String _span(DateTime? from, DateTime? to) {
    if (from == null || to == null) return '—';
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return '${hm(from)} → ${hm(to)}';
  }

  static String _iso(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _ago(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 48) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inDays}d';
  }

  Widget _row(String label, String value, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child:
                  Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
            ),
            Expanded(
              child: Text(
                value,
                style: AppText.bodySm(
                    color: warn ? AppColors.error : AppColors.onSurface),
              ),
            ),
          ],
        ),
      );
}
