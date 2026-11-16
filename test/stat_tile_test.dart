import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/widgets/ui/stat_tile.dart';

/// The sleep screen's 2x2 grid clipped every tile's value off the bottom
/// because the aspect ratio gave less height than the tile needs. These pin
/// the tile against the ratios that actually ship, at the narrowest phone width
/// and at a large text scale.
Future<void> pumpGrid(
  WidgetTester tester, {
  required double width,
  required double ratio,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: ratio,
            children: const [
              StatTile(
                  label: 'Wake-ups',
                  value: '0',
                  icon: Icons.nights_stay_rounded,
                  accent: AppColors.tertiary),
              StatTile(
                  label: 'Awake in bed',
                  value: '—',
                  icon: Icons.hourglass_bottom_rounded,
                  accent: AppColors.primary),
              StatTile(
                  label: 'Phone pickups',
                  value: '12',
                  icon: Icons.phone_android_rounded,
                  accent: AppColors.secondary),
              StatTile(
                  label: 'Sleep score',
                  value: '55',
                  unit: '/100',
                  icon: Icons.auto_awesome_rounded,
                  accent: AppColors.secondary),
            ],
          ),
        ),
      ),
    ),
  ));
}

void main() {
  // 1.3 on the sleep screen, 1.35 on the profile screen — both use this tile.
  for (final ratio in [1.3, 1.35]) {
    testWidgets('fits at ratio $ratio on a 320dp phone', (tester) async {
      await pumpGrid(tester, width: 320, ratio: ratio);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits at ratio $ratio on a 360dp phone', (tester) async {
      await pumpGrid(tester, width: 360, ratio: ratio);
      expect(tester.takeException(), isNull);
    });
  }

  // The tile has no fixed internal gap any more, so a taller cell should simply
  // spread rather than the value drifting off the bottom.
  testWidgets('fits in a much taller cell', (tester) async {
    await pumpGrid(tester, width: 360, ratio: 0.9);
    expect(tester.takeException(), isNull);
  });

  // A long label must ellipsize rather than wrap into the value's space.
  testWidgets('a long label does not push the value out', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 140,
          height: 108,
          child: StatTile(
            label: 'Time awake in bed last night',
            value: '1,234',
            unit: 'min',
            icon: Icons.hourglass_bottom_rounded,
            accent: AppColors.primary,
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('1,234'), findsOneWidget);
  });
}
