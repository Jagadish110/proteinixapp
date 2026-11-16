import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/core/theme/app_dimens.dart';
import 'package:proteinix/core/theme/app_typography.dart';
import 'package:proteinix/widgets/ui/ui.dart';

List<RingSpec> _rings({double steps = 4200, double water = 900}) => [
      RingSpec(
          label: 'Steps',
          current: steps,
          goal: 10000,
          color: AppColors.secondary),
      const RingSpec(
          label: 'Macros', current: 0.62, goal: 1, color: AppColors.primary),
      RingSpec(
          label: 'Water',
          current: water,
          goal: 2500,
          color: AppColors.water,
          unit: 'ml'),
      const RingSpec(
          label: 'Sleep',
          current: 6.5,
          goal: 8,
          color: AppColors.tertiary,
          unit: 'h'),
    ];

Future<Size> _measure(WidgetTester tester, double width,
    {List<RingSpec>? rings}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: TodayProgressPanel(
            title: "TODAY'S PROGRESS",
            rings: rings ?? _rings(),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(TodayProgressPanel));
}

/// The energy card's real contents, so the carousel height in home_screen.dart
/// is checked against what actually renders rather than an estimate.
Future<double> _cardHeight(WidgetTester tester, double width) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(child: SectionLabel('DAILY ENERGY')),
                Text('1200', style: AppText.headlineMd()),
              ]),
              const SizedBox(height: AppSpacing.sm),
              TodayProgressPanel(title: "TODAY'S PROGRESS", rings: _rings()),
              const SizedBox(height: AppSpacing.sm),
              const MacroGaugeRow(macros: [
                MacroSpec(
                    label: 'Protein',
                    current: 90,
                    goal: 150,
                    color: AppColors.protein,
                    icon: Icons.kebab_dining_rounded),
                MacroSpec(
                    label: 'Carbs',
                    current: 120,
                    goal: 260,
                    color: AppColors.carbs,
                    icon: Icons.bakery_dining_rounded),
                MacroSpec(
                    label: 'Fats',
                    current: 40,
                    goal: 70,
                    color: AppColors.fat,
                    icon: Icons.water_drop_rounded),
                MacroSpec(
                    label: 'Fiber',
                    current: 10,
                    goal: 25,
                    color: AppColors.fiber,
                    icon: Icons.eco_rounded),
              ]),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  // Plus the card's own vertical padding.
  return tester.getSize(find.byType(Column).first).height + AppSpacing.md * 2;
}

void main() {
  testWidgets('panel fits the energy card at narrow phone widths',
      (tester) async {
    // 320dp screen − 2×20 page − 2×2 card margin − 2×24 card padding.
    final size = await _measure(tester, 228);
    expect(size.height, lessThanOrEqualTo(110),
        reason: 'panel is ${size.height}px tall; the card budgets 110');
  });

  testWidgets('energy card fits the carousel at every phone width',
      (tester) async {
    // Must stay under the SizedBox height in home_screen's _carouselSection.
    const carouselHeight = 312.0;
    for (final width in [228.0, 268.0, 320.0, 400.0]) {
      final height = await _cardHeight(tester, width);
      expect(height, lessThanOrEqualTo(carouselHeight),
          reason: 'card is ${height}px at ${width}dp wide');
    }
  });

  testWidgets('legend does not overflow with five-figure step goals',
      (tester) async {
    await _measure(tester, 228, rings: _rings(steps: 0, water: 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed goals read as Done', (tester) async {
    await _measure(tester, 260, rings: _rings(steps: 12000, water: 3000));
    expect(find.text('Done'), findsNWidgets(2));
  });

  testWidgets('centre shows mean completion across the rings', (tester) async {
    await _measure(tester, 260, rings: [
      const RingSpec(label: 'A', current: 1, goal: 1, color: AppColors.primary),
      const RingSpec(label: 'B', current: 0, goal: 1, color: AppColors.water),
    ]);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('over-target rings never push the mean past 100%',
      (tester) async {
    await _measure(tester, 260, rings: [
      const RingSpec(label: 'A', current: 9, goal: 1, color: AppColors.primary),
      const RingSpec(label: 'B', current: 1, goal: 1, color: AppColors.water),
    ]);
    expect(find.text('100%'), findsOneWidget);
  });

  group('unmeasured rings', () {
    // Sleep records nothing unless Sleep Guard ran, so a zero has to read as
    // "not tracked" rather than as a goal comprehensively missed.
    testWidgets('read as a dash, not as a shortfall', (tester) async {
      await _measure(tester, 260, rings: [
        const RingSpec(
            label: 'Sleep',
            current: 0,
            goal: 8,
            color: AppColors.tertiary,
            unit: 'h',
            hasData: false),
      ]);

      expect(find.text('—'), findsOneWidget);
      expect(find.text('8.0h'), findsNothing);
    });

    // Otherwise the dashboard reads worse the less it knows: one untracked
    // night would take a quarter off a four-ring day.
    testWidgets('are excluded from the centre percentage', (tester) async {
      await _measure(tester, 260, rings: [
        const RingSpec(
            label: 'A', current: 1, goal: 1, color: AppColors.primary),
        const RingSpec(
            label: 'B',
            current: 0,
            goal: 1,
            color: AppColors.tertiary,
            hasData: false),
      ]);

      expect(find.text('100%'), findsOneWidget,
          reason: 'the measured ring is complete; the other is unknown');
    });

    testWidgets('a fully unmeasured panel reads as zero, not a crash',
        (tester) async {
      await _measure(tester, 260, rings: [
        const RingSpec(
            label: 'A',
            current: 0,
            goal: 8,
            color: AppColors.tertiary,
            hasData: false),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('still fits the card budget at narrow widths', (tester) async {
      final size = await _measure(tester, 228, rings: [
        ..._rings().take(3),
        const RingSpec(
            label: 'Sleep',
            current: 0,
            goal: 8,
            color: AppColors.tertiary,
            unit: 'h',
            hasData: false),
      ]);
      expect(size.height, lessThanOrEqualTo(110));
      expect(tester.takeException(), isNull);
    });
  });
}
