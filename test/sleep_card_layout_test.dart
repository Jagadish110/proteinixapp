import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/core/theme/app_dimens.dart';
import 'package:proteinix/core/theme/app_typography.dart';
import 'package:proteinix/services/sleep_tracking_service.dart';
import 'package:proteinix/widgets/sleep_cycle_switch.dart';
import 'package:proteinix/widgets/ui/ui.dart';

/// The sleep card shares a carousel slot with the energy card, so anything
/// added to it has to fit. The summary block grew from one line of text to an
/// hours line plus three counts — this pins that it still fits at the narrowest
/// phone width, and that raising the system text size grows the slot instead of
/// clipping the card.
const carouselHeight = 312.0;

/// Mirrors home_screen's `_carouselSection`, which scales the slot with the
/// text scale rather than clamping the text.
double slotFor(double textScale) => carouselHeight * textScale.clamp(1.0, 1.4);

/// Mirrors the card's structure in home_screen.dart: heading, times, summary,
/// cycle switch. Kept in step by hand — the card itself is private to that
/// file. The switch is the real widget, so its two lines of text are measured
/// rather than approximated.
Widget sleepCardBody({required bool withDetail}) => TerraCard(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('SLEEP CYCLE'),
              Text('ARMED', style: AppText.labelCaps(size: 9)),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              for (final label in ['SLEEP', 'WAKE'])
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IconBubble(
                          icon: Icons.bedtime_rounded,
                          color: AppColors.sleep,
                          size: 48,
                          tinted: true),
                      const SizedBox(height: 8),
                      Text(label, style: AppText.labelCaps(size: 10)),
                      const SizedBox(height: 2),
                      Text('10:30 PM',
                          style: AppText.bodyBold().copyWith(fontSize: 20)),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (withDetail) ...[
            Row(
              children: [
                const Icon(Icons.bedtime_rounded,
                    color: AppColors.sleep, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('6h 12m', style: AppText.bodyBold())),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final s in [
                  ('WAKE-UPS', '2'),
                  ('AWAKE', '48m'),
                  ('PICKUPS', '3'),
                ])
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.$2,
                            style: AppText.bodyBold().copyWith(fontSize: 15)),
                        const SizedBox(height: 1),
                        Text(s.$1, style: AppText.labelCaps(size: 8)),
                      ],
                    ),
                  ),
              ],
            ),
          ] else
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    color: AppColors.onSurfaceVariant, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('8h in bed', style: AppText.bodySm())),
              ],
            ),
          const SizedBox(height: 6),
          SleepCycleSwitch(
            status: SleepTrackingStatus.defaults,
            busy: false,
            onChanged: (_) {},
          ),
        ],
      ),
    );

Future<double> measure(
  WidgetTester tester, {
  required double width,
  required bool withDetail,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: SizedBox(
            height: slotFor(textScale),
            child: KeyedSubtree(
                key: key, child: sleepCardBody(withDetail: withDetail)),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byKey(key)).height;
}

void main() {
  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('sleep detail fits the carousel at ${width}dp', (tester) async {
      final h = await measure(tester, width: width, withDetail: true);
      expect(h, lessThanOrEqualTo(slotFor(1.0)));
    });
  }

  // The empty state is the other half of the same slot.
  testWidgets('the no-data card fits too', (tester) async {
    final h = await measure(tester, width: 320, withDetail: false);
    expect(h, lessThanOrEqualTo(slotFor(1.0)));
  });

  // Larger text is where a fixed-height card usually breaks.
  testWidgets('fits at a 1.15 text scale', (tester) async {
    final h = await measure(
        tester, width: 320, withDetail: true, textScale: 1.15);
    expect(h, lessThanOrEqualTo(slotFor(1.15)));
  });
}
