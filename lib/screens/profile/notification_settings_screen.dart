import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/crash_log.dart';
import '../../core/utils/require_account.dart';
import '../../services/notification_permission_service.dart';
import '../../models/meal_slot.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  late NotificationSettings _settings;

  // Reminders can be scheduled successfully yet still never actually fire.
  // The three gates below are independent, and failing any one of them looks
  // identical to the user, so all three are surfaced separately:
  //   • notifications off  → nothing is ever posted,
  //   • no exact alarms    → Android batches them, minutes-to-hours late,
  //   • battery managed    → OEM cleaners drop the alarm outright.
  bool _notificationsOk = false;

  /// Coalesces the burst of changes a slider or time picker produces — a full
  /// reschedule is ~20 platform round trips and shouldn't run per tick.
  Timer? _applyDebounce;

  static const _mealIcons = [
    Icons.wb_twilight_rounded,
    Icons.wb_sunny_rounded,
    Icons.nights_stay_rounded,
    Icons.bakery_dining_rounded,
    Icons.local_cafe_rounded,
  ];

  /// The shared schedule. Editing it here is what makes a rename or a new slot
  /// appear on the dashboard, the nutrition tab and log food.
  List<MealSlot> _slots = MealScheduleService.defaults;

  /// Persists the schedule and mirrors it into the reminder settings, which is
  /// what the scheduler actually reads. Both have to move together: the keys
  /// array is positional, so writing labels without keys would shift every
  /// slot's identity by one the moment a middle slot is removed.
  void _applySlots(List<MealSlot> next) {
    setState(() => _slots = next);
    ref.read(mealScheduleProvider.notifier).replace(next);
    _update(_settings.copyWith(
      mealTimes: [for (final s in next) s.time],
      mealLabels: [for (final s in next) s.label],
    ));
  }

  static const _mealPreset = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Evening'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _applyDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _settings = await NotificationService.load();
    _slots = await MealScheduleService.load();
    await _refreshPermissionState();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshPermissionState() async {
    final notifications = await NotificationService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationsOk = notifications);
  }

  // ── Applying changes ──────────────────────────────────────────────────────

  /// Updates state and schedules a background re-apply.
  ///
  /// Changes take effect without the user pressing Save — a reminder screen
  /// where the toggle is on but nothing was registered is exactly the failure
  /// mode being fixed here.
  void _update(NotificationSettings next, {bool apply = true}) {
    setState(() => _settings = next);
    if (!apply) return;
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 700), _applyNow);
  }

  Future<void> _applyNow() async {
    // Same gate as [_save], on the path that fires from simply flipping a
    // toggle. Silent here rather than showing the sheet — the sheet belongs to
    // a deliberate tap on "Save & schedule", not to a debounce timer landing
    // 700ms after a switch moved.
    if (!SupabaseService.isLoggedIn) return;

    final settings = _settings;
    try {
      await NotificationService.saveAndSchedule(settings);
    } catch (e, st) {
      // reschedule() swallows per-alarm failures internally, so reaching here
      // means something more fundamental broke (e.g. plugin init) — worth
      // keeping in the crash log for Profile → Diagnostics.
      await CrashLog.record('Notification reschedule failed: $e', st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Couldn't schedule reminders — see Diagnostics.")),
      );
    }
  }

  /// Gates a toggle behind the permissions Android needs before a reminder can
  /// be delivered. Returns false when the toggle should snap back off.
  Future<bool> _ensurePermissions() async {
    final blocker = await NotificationPermissionService.request(context);
    await _refreshPermissionState();
    if (!mounted) return false;

    switch (blocker) {
      case NotificationBlocker.none:
        return true;
      case NotificationBlocker.notificationsPermanentlyDenied:
        // The settings dialog was already shown by the permission service.
        return false;
      case NotificationBlocker.notificationsDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Reminders need notification permission to be delivered.'),
          ),
        );
        return false;
    }
  }

  /// Shared handler for all four reminder toggles.
  Future<void> _toggle(
    bool value,
    NotificationSettings Function(bool) build,
  ) async {
    if (!value) {
      _update(build(false));
      return;
    }
    if (!await _ensurePermissions()) {
      if (mounted) setState(() => _settings = build(false));
      return;
    }
    _update(build(true));
  }

  Future<void> _save() async {
    // Guests get the sign-up sheet instead of a schedule. The service refuses
    // to arm anything without an account anyway (see
    // `NotificationService.reschedule`), so without this the button would
    // report "Reminders scheduled." over a schedule that was silently dropped.
    if (!await requireAccount(context, action: 'get reminders')) return;
    if (!mounted) return;

    setState(() => _saving = true);
    _applyDebounce?.cancel();

    await NotificationService.savePreferences(_settings);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final on = _settings.anyEnabled;
    final settings = _settings;

    setState(() => _saving = false);
    Navigator.pop(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
            on ? 'Reminders saved — scheduling…' : 'All reminders turned off.'),
        duration: const Duration(seconds: 2),
      ),
    );

    // Continue on the static service so it survives this screen being popped.
    unawaited(NotificationService.reschedule(settings).then((_) {
      if (!on) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Reminders scheduled.')));
    }).catchError((Object e, StackTrace st) {
      unawaited(CrashLog.record('Notification reschedule failed: $e', st));
      messenger.showSnackBar(
        const SnackBar(
            content: Text("Couldn't schedule reminders — see Diagnostics.")),
      );
    }));
  }

  Future<void> _fixNotifications() async {
    await NotificationPermissionService.request(context);
    await _refreshPermissionState();
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      ),
      // Without this, the picker inherits the phone's system clock format —
      // a device set to 24-hour time got a 24-hour dial with no AM/PM toggle.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Reminders'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                  AppSpacing.page, AppSpacing.lg),
              children: [
                if (_reliabilityWarning() case final warning?) ...[
                  warning,
                  const SizedBox(height: AppSpacing.gutter),
                ],
                _waterCard(),
                const SizedBox(height: AppSpacing.gutter),
                _mealCard(),
                const SizedBox(height: AppSpacing.gutter),
                _stepCard(),
                const SizedBox(height: AppSpacing.gutter),
                _sleepCard(),
                const SizedBox(height: AppSpacing.lg),
                PillButton(
                  label: 'Save & schedule',
                  icon: Icons.notifications_active_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }

  // ── Reliability ───────────────────────────────────────────────────────
  Widget? _reliabilityWarning() {
    if (!_settings.anyEnabled) return null;
    // Notification permission is the only thing the app asks for, so it is the
    // only thing that can be missing.
    if (_notificationsOk) return null;
    return TerraCard(
      borderColor: AppColors.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text("Reminders can't be delivered",
                    style: AppText.bodyBold()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Android is blocking notifications for Proteinix, so nothing will '
            'arrive until this is turned on.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          _fixRow('Allow notifications', _fixNotifications),
        ],
      ),
    );
  }

  Widget _fixRow(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.bodySm())),
          MiniPill(
            label: 'Fix',
            onTap: onTap,
            background: AppColors.primary,
            foreground: AppColors.onPrimary,
          ),
        ],
      ),
    );
  }

  // ── Water ─────────────────────────────────────────────────────────────
  Widget _waterCard() {
    final s = _settings;
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toggleHeader(
            icon: Icons.water_drop_rounded,
            accent: AppColors.water,
            title: 'Water Reminders',
            subtitle: 'Every ${s.waterIntervalHours}h · '
                '${s.waterStartTime}–${s.waterEndTime}',
            value: s.waterEnabled,
            onChanged: (v) =>
                _toggle(v, (on) => _settings.copyWith(waterEnabled: on)),
          ),
          if (s.waterEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.outline),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('INTERVAL', style: AppText.labelCaps(size: 11)),
                Expanded(
                  child: Slider(
                    value: s.waterIntervalHours.toDouble(),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    activeColor: AppColors.water,
                    label: '${s.waterIntervalHours}h',
                    onChanged: (v) => _update(
                        _settings.copyWith(waterIntervalHours: v.round())),
                  ),
                ),
                Text('${s.waterIntervalHours}h',
                    style: AppText.bodyBold(color: AppColors.water)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _timeBlock('Start', s.waterStartTime, () async {
                    final t = await _pickTime(s.waterStartTime);
                    if (t != null) {
                      _update(_settings.copyWith(waterStartTime: t));
                    }
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeBlock('End', s.waterEndTime, () async {
                    final t = await _pickTime(s.waterEndTime);
                    if (t != null) {
                      _update(_settings.copyWith(waterEndTime: t));
                    }
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _waterTimes()
                  .map((t) => TerraBadge(label: t, color: AppColors.water))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Preview of the slots [NotificationService] will register — same minute
  /// handling, so a 08:30 start shows 08:30/10:30/… rather than 08:00/10:00/…
  List<String> _waterTimes() {
    int minutesOf(String hhmm, int fallbackHour) {
      final parts = hhmm.split(':');
      final h = int.tryParse(parts.first) ?? fallbackHour;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return h.clamp(0, 23) * 60 + m.clamp(0, 59);
    }

    final start = minutesOf(_settings.waterStartTime, 8);
    final end = minutesOf(_settings.waterEndTime, 22);
    final step = _settings.waterIntervalHours.clamp(1, 12) * 60;

    final out = <String>[];
    for (var t = start;
        t <= end && out.length < NotificationService.waterMaxSlots;
        t += step) {
      out.add('${(t ~/ 60).toString().padLeft(2, '0')}:'
          '${(t % 60).toString().padLeft(2, '0')}');
    }
    return out;
  }

  // ── Meals ─────────────────────────────────────────────────────────────
  Widget _mealCard() {
    final s = _settings;
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toggleHeader(
            icon: Icons.restaurant_rounded,
            accent: AppColors.secondary,
            title: 'Meal Reminders',
            subtitle: '${_slots.length} of ${MealScheduleService.maxSlots} '
                'meals — used across the whole app',
            value: s.mealEnabled,
            onChanged: (v) =>
                _toggle(v, (on) => _settings.copyWith(mealEnabled: on)),
          ),
          if (s.mealEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.outline),
            const SizedBox(height: AppSpacing.xs),
            ...List.generate(_slots.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    IconBubble(
                      icon: i < _mealIcons.length
                          ? _mealIcons[i]
                          : Icons.restaurant_rounded,
                      color: AppColors.secondary,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    // Tapping the name renames the slot. Labels were fixed
                    // presets before, so a "Pre-workout" or "Iftar" reminder
                    // had to borrow someone else's name.
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _renameMeal(i),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(_slots[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.bodyBold()),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit_outlined,
                                color: AppColors.onSurfaceVariant, size: 14),
                          ],
                        ),
                      ),
                    ),
                    MiniPill(
                      label: _slots[i].time,
                      foreground: AppColors.primary,
                      onTap: () async {
                        final t = await _pickTime(_slots[i].time);
                        if (t == null) return;
                        final next = List<MealSlot>.from(_slots)
                          ..[i] = _slots[i].copyWith(time: t);
                        _applySlots(next);
                      },
                    ),
                    if (_slots.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: AppColors.error, size: 20),
                        onPressed: () => _removeMeal(i),
                      ),
                  ],
                ),
              );
            }),
            if (_slots.length < MealScheduleService.maxSlots) ...[
              const SizedBox(height: AppSpacing.sm),
              PillButton(
                label: 'Add reminder',
                tone: PillTone.neutral,
                icon: Icons.add_rounded,
                height: 46,
                glow: false,
                onPressed: () {
                  final index = _slots.length;
                  _applySlots([
                    ..._slots,
                    MealSlot(
                      // Keys are permanent, so a new slot never reuses one a
                      // removed slot might still own rows under.
                      key: MealScheduleService.newKey(_slots),
                      label: index < _mealPreset.length
                          ? _mealPreset[index]
                          : 'Meal ${index + 1}',
                      time: '12:00',
                    ),
                  ]);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Renames one meal slot. The label is what the notification says, so an
  /// empty name would ship a blank reminder — blanks are discarded.
  Future<void> _renameMeal(int index) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _MealNameDialog(initial: _slots[index].label),
    );
    if (name == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _slots[index].label) return;

    // Only the label moves — the key stays put, so meals already logged to
    // this slot keep showing up under its new name.
    _applySlots(List<MealSlot>.from(_slots)
      ..[index] = _slots[index].copyWith(label: trimmed));
  }

  Future<void> _removeMeal(int index) async {
    // Every later slot shifts down one id, so cancelling just this slot would
    // strand the last alarm in the range — clear the whole meal block and let
    // the re-apply below register the remaining slots afresh.
    await NotificationService.cancelMeals();
    if (!mounted) return;
    _applySlots(List<MealSlot>.from(_slots)..removeAt(index));
  }

  // ── Steps ─────────────────────────────────────────────────────────────
  Widget _stepCard() {
    return TerraCard(
      child: _toggleHeader(
        icon: Icons.directions_walk_rounded,
        accent: AppColors.secondaryContainer,
        title: 'Step Reminders',
        subtitle: 'Check-ins at 12:00 and 20:00',
        value: _settings.stepEnabled,
        onChanged: (v) =>
            _toggle(v, (on) => _settings.copyWith(stepEnabled: on)),
      ),
    );
  }

  // ── Sleep ─────────────────────────────────────────────────────────────
  Widget _sleepCard() {
    final s = _settings;
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toggleHeader(
            icon: Icons.bedtime_rounded,
            accent: AppColors.tertiary,
            title: 'Bedtime Reminder',
            subtitle: '30 minutes before ${s.sleepBedtime}',
            value: s.sleepEnabled,
            onChanged: (v) =>
                _toggle(v, (on) => _settings.copyWith(sleepEnabled: on)),
          ),
          if (s.sleepEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.outline),
            const SizedBox(height: AppSpacing.sm),
            _timeBlock('Bedtime', s.sleepBedtime, () async {
              final t = await _pickTime(s.sleepBedtime);
              if (t != null) _update(_settings.copyWith(sleepBedtime: t));
            }),
          ],
        ],
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────
  Widget _toggleHeader({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        IconBubble(icon: icon, color: accent, size: 44, tinted: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.headlineMd()),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _timeBlock(String label, String time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: AppRadius.xlR,
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
            const SizedBox(height: 4),
            Text(time, style: AppText.data(color: AppColors.water)),
          ],
        ),
      ),
    );
  }
}

/// Rename prompt for a meal reminder slot.
///
/// Owns its controller so it is disposed with the dialog — creating it in the
/// caller leaks it when the dialog is dismissed by the back gesture.
class _MealNameDialog extends StatefulWidget {
  const _MealNameDialog({required this.initial});

  final String initial;

  @override
  State<_MealNameDialog> createState() => _MealNameDialogState();
}

class _MealNameDialogState extends State<_MealNameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text('Rename reminder', style: AppText.headlineMd()),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: AppText.body(),
        decoration: const InputDecoration(
          hintText: 'e.g. Pre-workout',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: AppText.bodyBold(color: AppColors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: _submit,
          child:
              Text('Save', style: AppText.bodyBold(color: AppColors.primary)),
        ),
      ],
    );
  }
}
