import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/core/theme/app_dimens.dart';
import 'package:proteinix/models/user_profile.dart';
import 'package:proteinix/screens/progress/progress_screen.dart';

/// The metric cards live in a PageView, which needs a fixed slot height — and a
/// fixed height is what clipped the sleep stat grid and the sleep carousel card
/// earlier. These measure every metric instead of trusting an estimate.
///
/// Sleep is the tall one: it carries a fifth stat row the others don't.
const slotAtDefaultScale = 372.0;

double slotFor(double textScale) =>
    slotAtDefaultScale * textScale.clamp(1.0, 1.4);

List<Map<String, dynamic>> logsFor(int days) => [
      for (var i = 0; i < days; i++)
        {
          'date': '2026-08-${(i + 1).toString().padLeft(2, '0')}',
          'calories_consumed': 1850 + i,
          'protein_g': 120.0,
          'water_ml': 2400,
          'steps': 8500,
          'sleep_hrs': 7.4,
          'sleep_interruptions': 2,
        },
    ];

Future<double> measure(
  WidgetTester tester, {
  required ProgressMetric metric,
  required double width,
  double textScale = 1.0,
  int days = 7,
}) async {
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: KeyedSubtree(
              key: key,
              child: ProgressMetricCard(
                metric: metric,
                logs: logsFor(days),
                profile: UserProfile(id: 'u1'),
                loading: false,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 1000));
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byKey(key)).height;
}

void main() {
  group('every metric fits the page slot', () {
    for (final metric in ProgressMetric.values) {
      testWidgets('${metric.label} at 320dp', (tester) async {
        final h = await measure(tester, metric: metric, width: 320);
        expect(h, lessThanOrEqualTo(slotFor(1.0)),
            reason: '${metric.label} needs ${h}px of ${slotFor(1.0)}');
      });
    }
  });

  testWidgets('sleep — the tallest — fits at 360dp too', (tester) async {
    final h =
        await measure(tester, metric: ProgressMetric.sleep, width: 360);
    expect(h, lessThanOrEqualTo(slotFor(1.0)));
  });

  // The slot scales with the text scale rather than clamping the text.
  testWidgets('sleep fits at a 1.15 text scale', (tester) async {
    final h = await measure(
        tester, metric: ProgressMetric.sleep, width: 320, textScale: 1.15);
    expect(h, lessThanOrEqualTo(slotFor(1.15)));
  });

  // An empty range renders a placeholder instead of the chart, and a long
  // range renders many points — neither should change the card's height.
  testWidgets('no data fits', (tester) async {
    final h = await measure(
        tester, metric: ProgressMetric.sleep, width: 320, days: 0);
    expect(h, lessThanOrEqualTo(slotFor(1.0)));
  });

  testWidgets('a 90-day range fits', (tester) async {
    final h = await measure(
        tester, metric: ProgressMetric.calories, width: 320, days: 90);
    expect(h, lessThanOrEqualTo(slotFor(1.0)));
  });
}
