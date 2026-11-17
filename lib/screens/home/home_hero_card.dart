import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../models/daily_log.dart';
import '../../models/user_profile.dart';
import '../../widgets/ui/ui.dart';

/// The dashboard's hero: calories left as a ring, protein as the biggest
/// number on the screen, and carbs, fat and fibre as bars underneath.
///
/// Deep green, the one strongly coloured card on the home screen, so the
/// eye lands here first. Steps, water and sleep have their own cards below
/// and on the next carousel page, so they are not repeated here.
class EnergyHeroCard extends StatelessWidget {
  const EnergyHeroCard({super.key, required this.profile, required this.log});

  final UserProfile? profile;
  final DailyLog? log;

  // The hero card's own palette: light ink on the deep green. Every pairing
  // here reads at 4.5:1 or better against AppColors.primary.
  static const _muted = AppColors.primaryFixed;
  static const _track = Color(0xFF14784F);
  static const _bar = AppColors.primaryFixedDim;
  static const _highlight = Color(0xFFFFD27A);

  static double _ratio(double current, double goal) =>
      goal <= 0 ? 0 : (current / goal).clamp(0.0, 1.0).toDouble();

  static String _thousands(int n) => NumberFormat.decimalPattern().format(n);

  @override
  Widget build(BuildContext context) {
    final goal = profile?.calorieGoal ?? 2000;
    final eaten = log?.caloriesConsumed ?? 0;
    final over = eaten > goal;
    final left = (goal - eaten).abs();

    final protein = log?.proteinG ?? 0;
    final proteinGoal = profile?.proteinGoalG ?? 150;
    final proteinLeft = proteinGoal - protein;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.cardR,
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_thousands(eaten)} of ${_thousands(goal)} kcal eaten',
            style: AppText.bodySm(color: _muted)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Row(
            children: [
              ProgressRing(
                value: _ratio(eaten.toDouble(), goal.toDouble()),
                color: over
                    ? AppColors.tertiaryFixedDim
                    : AppColors.secondaryContainer,
                trackColor: _track,
                size: 112,
                strokeWidth: 12,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _thousands(left),
                        style: AppText.data(color: AppColors.onPrimary)
                            .copyWith(fontSize: 26, height: 1),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      over ? 'kcal over' : 'kcal left',
                      style: AppText.bodySm(color: _muted)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PROTEIN TODAY',
                        style: AppText.labelCaps(color: _muted, size: 11)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: protein.round().toString()),
                            TextSpan(
                              text: ' / ${proteinGoal.round()} g',
                              style: AppText.headlineMd(color: _muted),
                            ),
                          ],
                        ),
                        style: AppText.data(color: AppColors.onPrimary)
                            .copyWith(fontSize: 34, height: 1.1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      proteinLeft > 0.5
                          ? '${proteinLeft.round()} g to go'
                          : 'Goal met',
                      style: AppText.bodyBold(color: _highlight)
                          .copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _macro(
                    'Carbs', log?.carbsG ?? 0, profile?.carbsGoalG ?? 260),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _macro('Fat', log?.fatG ?? 0, profile?.fatGoalG ?? 70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _macro(
                    'Fibre', log?.fiberG ?? 0, profile?.fiberGoalG ?? 25),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String label, double current, double goal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySm(color: _muted),
              ),
            ),
            // Shrinks rather than overflowing when a large text size meets
            // a narrow phone; the label beside it ellipsises first.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${current.round()} g',
                  style: AppText.bodySm(color: AppColors.onPrimary)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: _ratio(current, goal),
            minHeight: 6,
            color: _bar,
            backgroundColor: _track,
          ),
        ),
      ],
    );
  }
}
