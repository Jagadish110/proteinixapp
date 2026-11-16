import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import 'progress_ring.dart';

/// Concentric goal rings beside a legend of what each one still owes.
///
/// Deliberately dumb: callers hand it finished [RingSpec]s so the layout can be
/// laid out and measured without a profile, a log, or a provider scope.
class TodayProgressPanel extends StatelessWidget {
  const TodayProgressPanel({
    super.key,
    required this.title,
    required this.rings,
    this.ringSize = 104,
  });

  final String title;
  final List<RingSpec> rings;

  /// Diameter of the concentric stack. The legend beside it is only ~80px
  /// tall, so the rings — not the text — set the panel height; they are sized
  /// to the card's 110px budget rather than left at the legend's height.
  final double ringSize;

  /// Mean completion across the rings that were actually measured, 0.0 – 1.0.
  ///
  /// Unmeasured rings are excluded rather than averaged in as zero: a night
  /// the sleep guard was off would otherwise take a quarter off the day's
  /// figure, making the dashboard read worse the less it knows.
  double get _covered {
    final known = rings.where((r) => r.hasData);
    if (known.isEmpty) return 0;
    return known.map((r) => r.ratio.clamp(0.0, 1.0)).reduce((a, b) => a + b) /
        known.length;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProgressRings(
          rings: rings,
          size: ringSize,
          strokeWidth: 8.5,
          center: Text('${(_covered * 100).round()}%',
              style: AppText.bodyBold().copyWith(fontSize: 17)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // "LEFT" is a column heading rather than a suffix on every row —
              // at 320dp the repeated word pushed the legend into an overflow.
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.labelCaps(size: 10)),
                  ),
                  const SizedBox(width: 4),
                  Text('LEFT', style: AppText.labelCaps(size: 9)),
                ],
              ),
              const SizedBox(height: 5),
              for (final r in rings) _LegendRow(spec: r),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.spec});

  final RingSpec spec;

  @override
  Widget build(BuildContext context) {
    final done = spec.remaining <= 0;
    final unknown = !spec.hasData;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: unknown ? spec.color.withValues(alpha: 0.3) : spec.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelCaps(
                  color: AppColors.onSurfaceVariant, size: 10),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unknown
                ? '—'
                : done
                    ? 'Done'
                    : '${_short(spec.remaining)}${spec.unit}',
            maxLines: 1,
            style: AppText.labelCaps(
              color: unknown
                  ? AppColors.onSurfaceVariant
                  : done
                      ? spec.color
                      : AppColors.onSurface,
              size: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Steps run to five figures and water to four — both need shortening to sit
  /// in the legend's right-hand column.
  static String _short(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    if (v >= 10) return v.round().toString();
    return v.toStringAsFixed(1);
  }
}
