import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/daily_log.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

/// Nutrition tab: a focused read-out of today's energy balance plus the full
/// logged-meal breakdown.
class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final profile = ref.watch(profileProvider).value;
    final log = ref.watch(dailyLogProvider(date));
    final meals = ref.watch(mealsForDateProvider(date));
    final isToday = AppDateUtils.toDateOnly(DateTime.now()) ==
        AppDateUtils.toDateOnly(date);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs,
              AppSpacing.page, AppSpacing.navClearance),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Nutrition', style: AppText.headlineLg()),
                CircleIconButton(
                  icon: Icons.calendar_today_rounded,
                  color: AppColors.primary,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      ref.read(selectedDateProvider.notifier).state =
                          AppDateUtils.toDateOnly(picked);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (!isToday) ...[
              Center(
                child: TerraBadge(
                  label: AppDateUtils.iso(date),
                  icon: Icons.history_rounded,
                  color: AppColors.tertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _SummaryCard(profile: profile, log: log),
            const SizedBox(height: AppSpacing.gutter),
            _ProteinGoalCard(profile: profile, log: log),
            const SizedBox(height: AppSpacing.lg),
            SectionHeading(
              'Logged Meals',
              actionLabel: 'Scan Food',
              onAction: () => context.push('/scan'),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Straight from Hive — present or genuinely empty, never pending.
            _MealBreakdown(meals: meals, date: date),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.profile, required this.log});

  final UserProfile? profile;
  final DailyLog? log;

  @override
  Widget build(BuildContext context) {
    final goal = profile?.calorieGoal ?? 2000;
    final eaten = log?.caloriesConsumed ?? 0;

    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's\nSummary",
                        style: AppText.display()
                            .copyWith(fontSize: 30, height: 1.15)),
                    const SizedBox(height: 8),
                    Text('$eaten / $goal kcal',
                        style: AppText.body(color: AppColors.onSurfaceVariant)
                            .copyWith(fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  const IconBubble(
                    icon: Icons.bolt_rounded,
                    color: AppColors.primaryContainer,
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  MiniPill(
                    label: '+ Log Food',
                    background: AppColors.primary,
                    foreground: AppColors.onPrimary,
                    border: AppColors.primary,
                    onTap: () => context.push('/log-food'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MacroGaugeRow(
            gap: 14,
            macros: [
              MacroSpec(
                label: 'Protein',
                current: log?.proteinG ?? 0,
                goal: profile?.proteinGoalG ?? 150,
                color: AppColors.protein,
                icon: Icons.kebab_dining_rounded,
              ),
              MacroSpec(
                label: 'Carbs',
                current: log?.carbsG ?? 0,
                goal: profile?.carbsGoalG ?? 260,
                color: AppColors.carbs,
                icon: Icons.bakery_dining_rounded,
              ),
              MacroSpec(
                label: 'Fats',
                current: log?.fatG ?? 0,
                goal: profile?.fatGoalG ?? 70,
                color: AppColors.fat,
                icon: Icons.water_drop_rounded,
              ),
              MacroSpec(
                label: 'Fiber',
                current: log?.fiberG ?? 0,
                goal: profile?.fiberGoalG ?? 25,
                color: AppColors.fiber,
                icon: Icons.eco_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProteinGoalCard extends StatelessWidget {
  const _ProteinGoalCard({required this.profile, required this.log});

  final UserProfile? profile;
  final DailyLog? log;

  @override
  Widget build(BuildContext context) {
    final goal = profile?.proteinGoalG ?? 150;
    final eaten = log?.proteinG ?? 0;
    final remaining = (goal - eaten).clamp(0, goal);
    final met = remaining <= 0;

    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Protein Goal', style: AppText.headlineMd()),
                    const SizedBox(height: 4),
                    Text(
                      met
                          ? 'Target reached — nice work'
                          : '${remaining.round()}g remaining to hit target',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text('${goal.round()}g',
                  style: AppText.display(color: AppColors.primary)
                      .copyWith(fontSize: 32)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('total',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearMeter(
            value: goal <= 0 ? 0 : eaten / goal,
            color: AppColors.primary,
            height: 12,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.bolt_rounded,
                  color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  met
                      ? 'Keep the rest of your macros balanced through the evening.'
                      : 'Focus on high-protein snacks this afternoon.',
                  style: AppText.bodyBold(color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealBreakdown extends ConsumerWidget {
  const _MealBreakdown({required this.meals, required this.date});

  final List<Meal> meals;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (meals.isEmpty) {
      return TerraEmptyState(
        icon: Icons.restaurant_menu_rounded,
        title: 'Nothing logged yet',
        message: 'Capture a photo or describe your meal to get started.',
        accent: AppColors.primary,
        action: SizedBox(
          width: 200,
          child: PillButton(
            label: 'Log food',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/log-food'),
          ),
        ),
      );
    }

    final slots = ref.watch(mealScheduleProvider);
    // Keys of meals whose slot has since been deleted are appended so the food
    // stays reachable instead of disappearing from the breakdown.
    final types = [
      for (final s in slots) s.key,
      ...{for (final m in meals) m.mealType}
          .where((k) => !slots.any((s) => s.key == k)),
    ];

    return Column(
      children: types.map((type) {
        final items = meals.where((m) => m.mealType == type).toList();
        final kcal = items.fold<int>(0, (s, m) => s + m.calories);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TerraCard(
            padding: EdgeInsets.zero,
            elevated: false,
            dimmed: items.isEmpty,
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 6),
                childrenPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xs),
                title: Row(
                  children: [
                    IconBubble(
                      icon: MealSlotStyle.icon(type),
                      color: AppColors.primary,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(MealScheduleService.labelFor(slots, type),
                              style: AppText.headlineMd()),
                          Text(
                            items.isEmpty
                                ? 'Tap to log items'
                                : '${items.length} item${items.length == 1 ? '' : 's'}',
                            style: AppText.bodySm(
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text('$kcal kcal',
                        style: AppText.bodyBold(color: AppColors.primary)),
                  ],
                ),
                children: items.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PillButton(
                            label:
                                'Log ${MealScheduleService.labelFor(slots, type)}',
                            tone: PillTone.neutral,
                            icon: Icons.add_rounded,
                            height: 46,
                            glow: false,
                            onPressed: () =>
                                context.push('/log-food', extra: type),
                          ),
                        )
                      ]
                    : items.map((m) => _MealRow(meal: m, date: date)).toList(),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MealRow extends ConsumerWidget {
  const _MealRow({required this.meal, required this.date});

  final Meal meal;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppRadius.xlR,
      ),
      child: Row(
        children: [
          FoodIcon(foodName: meal.foodName, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.foodName, style: AppText.bodyBold()),
                const SizedBox(height: 2),
                Text(
                  'P ${meal.proteinG.toStringAsFixed(0)}g · '
                  'C ${meal.carbsG.toStringAsFixed(0)}g · '
                  'F ${meal.fatG.toStringAsFixed(0)}g',
                  style: AppText.labelCaps(size: 10),
                ),
              ],
            ),
          ),
          Text('${meal.calories} kcal',
              style: AppText.bodyBold(color: AppColors.primary)),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.onSurfaceVariant, size: 18),
            onPressed: () async {
              final uid = SupabaseService.currentUserId;
              if (uid == null) return;
              await MealService.deleteMeal(ref, uid, meal.id, date);
            },
          ),
        ],
      ),
    );
  }
}
