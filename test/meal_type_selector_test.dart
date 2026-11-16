import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_dimens.dart';
import 'package:proteinix/widgets/ui/ui.dart';

const _options = [
  MealTypeOption(value: 'breakfast', icon: Icons.free_breakfast_rounded),
  MealTypeOption(value: 'lunch', icon: Icons.lunch_dining_rounded),
  MealTypeOption(value: 'snack', icon: Icons.bakery_dining_rounded),
  MealTypeOption(value: 'dinner', icon: Icons.dinner_dining_rounded),
];

Future<void> _pump(
  WidgetTester tester, {
  required double screenWidth,
  double textScale = 1.0,
  String selected = 'breakfast',
  ValueChanged<String>? onSelected,
  List<MealTypeOption> options = _options,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            // The screen's list padding, as in log_food_screen.
            width: screenWidth - AppSpacing.page * 2,
            child: MealTypeSelector(
              options: options,
              selected: selected,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // The old childAspectRatio: 2.1 gave a 63px cell to a ~92px tile at 320dp.
  testWidgets('does not overflow at any phone width', (tester) async {
    for (final width in [320.0, 360.0, 411.0, 480.0, 600.0]) {
      await _pump(tester, screenWidth: width);
      expect(tester.takeException(), isNull, reason: '${width}dp');
    }
  });

  testWidgets('does not overflow with accessibility text scaling',
      (tester) async {
    for (final scale in [1.3, 1.6, 2.0]) {
      await _pump(tester, screenWidth: 320, textScale: scale);
      expect(tester.takeException(), isNull, reason: 'textScale $scale');
    }
  });

  testWidgets('grows the tile instead of clipping it', (tester) async {
    await _pump(tester, screenWidth: 320);
    final small = tester.getSize(find.byType(MealTypeTile).first).height;

    await _pump(tester, screenWidth: 320, textScale: 2.0);
    final large = tester.getSize(find.byType(MealTypeTile).first).height;

    expect(large, greaterThan(small));
  });

  testWidgets('tiles in a row share a height', (tester) async {
    await _pump(tester, screenWidth: 360);
    final heights = tester
        .widgetList(find.byType(MealTypeTile))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(heights, hasLength(1));
  });

  testWidgets('renders every option and reports taps', (tester) async {
    String? tapped;
    await _pump(tester, screenWidth: 360, onSelected: (t) => tapped = t);

    expect(find.byType(MealTypeTile), findsNWidgets(4));
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);

    await tester.tap(find.text('Snack'));
    expect(tapped, 'snack');
  });

  testWidgets('an odd option count leaves the last row aligned',
      (tester) async {
    await _pump(tester,
        screenWidth: 360, options: _options.sublist(0, 3), selected: 'lunch');

    expect(tester.takeException(), isNull);
    expect(find.byType(MealTypeTile), findsNWidgets(3));
    // The lone tile keeps a column's width rather than stretching across.
    final first = tester.getSize(find.byType(MealTypeTile).first).width;
    final last = tester.getSize(find.byType(MealTypeTile).last).width;
    expect(last, moreOrLessEquals(first, epsilon: 0.5));
  });
}
