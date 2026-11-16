import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/widgets/ui/ui.dart';

/// Lays the strip out in a fixed width, the way a meal row constrains it.
Future<void> pump(WidgetTester tester, double width, List<String> names,
    {double textScale = 1.0}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          // Mirrors the real constraint chain: TerraListRow puts the strip
          // inside Expanded > Column, so it receives a bounded width.
          child: Center(
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [FoodIconStrip(foodNames: names)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> foods(int n) => [for (var i = 0; i < n; i++) 'Food $i'];

void main() {
  // The bug: five icons were shown regardless of the room available, which
  // overflowed a meal row by 2.8 pixels on a narrow screen.
  testWidgets('never overflows, however little room it is given',
      (tester) async {
    for (final width in [40.0, 60.0, 90.0, 120.0, 155.0, 200.0, 320.0]) {
      await pump(tester, width, foods(8));
      expect(tester.takeException(), isNull, reason: 'at ${width}px wide');
    }
  });

  testWidgets('does not overflow at large text scales', (tester) async {
    await pump(tester, 120, foods(8), textScale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows every icon when they all fit', (tester) async {
    await pump(tester, 320, foods(4));
    expect(find.byType(FoodIcon), findsNWidgets(4));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('collapses the remainder into a +n chip', (tester) async {
    await pump(tester, 120, foods(8));
    final shown = tester.widgetList(find.byType(FoodIcon)).length;
    expect(shown, lessThan(8));
    expect(find.text('+${8 - shown}'), findsOneWidget);
  });

  // The chip needs room too. Sizing the icons to the full width and then
  // adding the chip is what would push the row over its budget.
  testWidgets('the +n chip is counted in the width it fits to',
      (tester) async {
    await pump(tester, 90, foods(6));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('+'), findsOneWidget);
  });

  testWidgets('renders nothing for an empty meal', (tester) async {
    await pump(tester, 200, const []);
    expect(find.byType(FoodIcon), findsNothing);
  });
}
