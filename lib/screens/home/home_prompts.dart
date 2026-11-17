import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/meal_slot.dart';
import '../../providers/daily_log_provider.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../services/routine_logger.dart';
import '../../services/routine_service.dart';
import '../../services/supabase_service.dart';
import '../../services/welcome_back_service.dart';
import '../../widgets/ui/ui.dart';

/// "Welcome back" for someone who has missed a day or more.
///
/// Shown in place of any comment on the streak. Renders nothing for everyone
/// else, and nothing once dismissed.
class WelcomeBackCard extends StatefulWidget {
  const WelcomeBackCard({super.key, this.name});

  final String? name;

  @override
  State<WelcomeBackCard> createState() => _WelcomeBackCardState();
}

class _WelcomeBackCardState extends State<WelcomeBackCard> {
  int _missed = 0;

  @override
  void initState() {
    super.initState();
    WelcomeBackService.checkIn().then((missed) {
      if (mounted && missed > 0) setState(() => _missed = missed);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_missed < 1) return const SizedBox.shrink();
    final first = widget.name?.trim().split(' ').first ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TerraCard(
        borderColor: AppColors.secondary.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBubble(
              icon: Icons.waving_hand_rounded,
              color: AppColors.secondary,
              size: 40,
              tinted: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.isEmpty ? 'Welcome back' : 'Welcome back, $first',
                    style: AppText.headlineMd(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    WelcomeBackService.message(_missed),
                    style: AppText.body(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.onSurfaceVariant),
              onPressed: () {
                WelcomeBackService.dismiss();
                setState(() => _missed = 0);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your usual breakfast" — the saved meal this user normally logs for the
/// meal slot the clock is in, loggable in one tap.
///
/// Only appears when it is useful: there is a usual meal for the current
/// slot, and nothing has been logged in that slot yet today. Renders nothing
/// otherwise, including for a signed-out guest.
class UsualMealCard extends ConsumerStatefulWidget {
  const UsualMealCard({super.key});

  @override
  ConsumerState<UsualMealCard> createState() => _UsualMealCardState();
}

class _UsualMealCardState extends ConsumerState<UsualMealCard> {
  List<SavedRoutine> _routines = const [];
  RoutineUsage _usage = RoutineUsage.empty;
  bool _logging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      final routines = await RoutineService.loadAll(uid);
      final usage = await RoutineUsage.load();
      if (!mounted) return;
      setState(() {
        _routines = routines;
        _usage = usage;
      });
    } catch (_) {}
  }

  Future<void> _log(SavedRoutine routine, MealSlot slot) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null || _logging) return;
    setState(() => _logging = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final kcal = await RoutineLogger.log(
        ref,
        uid: uid,
        routine: routine,
        mealType: slot.key,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('${routine.name} added to ${slot.label} — '
              '$kcal kcal.')));
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text("Couldn't log ${routine.name} — try again.")));
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_routines.isEmpty) return const SizedBox.shrink();

    final slots = ref.watch(mealScheduleProvider);
    if (slots.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final key = MealScheduleService.currentKey(slots, now);
    final slot =
        slots.firstWhere((s) => s.key == key, orElse: () => slots.first);

    // Already eaten: the suggestion has done its job, or was not needed.
    final today = AppDateUtils.toDateOnly(now);
    final meals = ref.watch(mealsForDateProvider(today));
    if (meals.any((m) => m.mealType == slot.key)) {
      return const SizedBox.shrink();
    }

    final usual = _usage.usualFor(_routines, slot);
    if (usual == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TerraCard(
        child: Row(
          children: [
            IconBubble(
              icon: MealSlotStyle.icon(slot.key, label: slot.label),
              color: AppColors.primary,
              size: 44,
              tinted: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR USUAL ${slot.label.toUpperCase()}',
                      style:
                          AppText.labelCaps(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(usual.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyBold()),
                  Text(
                    '${usual.totalCalories} kcal · '
                    '${usual.totalProtein.toStringAsFixed(0)}g protein',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MiniPill(
              label: _logging ? 'Logging…' : 'Log',
              icon: Icons.add_rounded,
              background: AppColors.primary,
              foreground: AppColors.onPrimary,
              onTap: _logging ? null : () => _log(usual, slot),
            ),
          ],
        ),
      ),
    );
  }
}
